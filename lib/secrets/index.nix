{ lib, ... }:
let
  inherit (builtins)
    attrNames
    concatLists
    elem
    filter
    foldl'
    hasAttr
    listToAttrs
    match
    sort
    ;
  inherit (lib)
    concatMapAttrs
    concatStringsSep
    filterAttrs
    hasAttrByPath
    mapAttrsToList
    nameValuePair
    unique
    ;

  sortedAttrNames = attrs: sort builtins.lessThan (attrNames attrs);

  mkKeyError = message: throw "secret index error: ${message}";

  assertPublicKey =
    targetId: value:
    if !(builtins.isString value) || value == "" then
      mkKeyError "${targetId} must define a non-empty secrets.publicKey"
    else if match "ssh-(ed25519|rsa) .+" value == null then
      mkKeyError "${targetId} has unsupported secrets.publicKey type"
    else
      value;

  assertGroups =
    targetId: groupNames:
    if !builtins.isList groupNames then
      mkKeyError "${targetId} must define secrets.groups as a list"
    else if builtins.any (group: !(builtins.isString group) || group == "") groupNames then
      mkKeyError "${targetId} has an invalid secrets.groups entry"
    else
      sort builtins.lessThan (unique groupNames);

  joinPath = parts: concatStringsSep "/" parts;
  joinId = parts: concatStringsSep "." parts;

  stripSecrets = attrs: builtins.removeAttrs attrs [ "secrets" ];

  mkSecretSpec =
    {
      topGroup,
      pathParts,
      name,
      spec,
    }:
    let
      pathDisplay = concatStringsSep "/" (pathParts ++ [ "${name}.age" ]);
      pathError = message: mkKeyError "${topGroup}/${pathDisplay} ${message}";
      scope = if pathParts == [ ] then "shared" else builtins.head pathParts;
      rest = if pathParts == [ ] then [ ] else builtins.tail pathParts;
      selector =
        if scope == "shared" then
          null
        else if scope == "home" then
          if rest == [ ] then null else builtins.head rest
        else if scope == "system" then
          if rest == [ ] then
            null
          else if builtins.head rest == "nixos" || builtins.head rest == "darwin" then
            if builtins.tail rest == [ ] then null else builtins.head (builtins.tail rest)
          else
            pathError "must use system/nixos/ or system/darwin/ for system-scoped secrets"
        else
          pathError "must use the group root, home/, or system/";
      platform =
        if scope != "system" then
          null
        else if rest == [ ] then
          null
        else
          builtins.head rest;
      relDir = joinPath (
        [
          "secrets"
          topGroup
        ]
        ++ pathParts
      );
    in
    {
      group = topGroup;
      inherit scope selector platform;
      agenixName = name;
      inherit (spec) file;
      fileRel = "${relDir}/${name}.age";
    };

  secretAppliesToTarget =
    secret: target:
    elem secret.group target.groups
    && (
      if secret.scope == "shared" then
        true
      else if secret.scope == "home" then
        target.targetType == "home" && (secret.selector == null || secret.selector == target.username)
      else if secret.scope == "system" then
        target.targetType == "host"
        && (secret.platform == null || secret.platform == target.platform)
        && (secret.selector == null || secret.selector == target.configName)
      else
        false
    );

  flattenGroupNode =
    {
      topGroup,
      pathParts ? [ ],
      node,
    }:
    let
      here =
        if hasAttrByPath [ "secrets" ] node then
          listToAttrs (
            mapAttrsToList (
              name: spec:
              nameValuePair (joinId ([ topGroup ] ++ pathParts ++ [ name ])) (mkSecretSpec {
                inherit
                  topGroup
                  pathParts
                  name
                  spec
                  ;
              })
            ) node.secrets
          )
        else
          { };

      children = concatMapAttrs (
        childName: childNode:
        flattenGroupNode {
          inherit topGroup;
          pathParts = pathParts ++ [ childName ];
          node = childNode;
        }
      ) (stripSecrets node);
    in
    here // children;

  flattenSecretsTree =
    secretsTree:
    concatMapAttrs (
      group: groupData:
      flattenGroupNode {
        topGroup = group;
        node = groupData;
      }
    ) secretsTree;

  normalizeTarget =
    {
      targetId,
      targetType,
      configData,
    }:
    let
      secretConfig = configData.secrets or { };
    in
    {
      inherit targetId targetType;
      username = configData.username or null;
      configName = configData.folderName or null;
      platform = configData.secretPlatform or null;
      publicKey = assertPublicKey targetId (secretConfig.publicKey or null);
      groups = assertGroups targetId (secretConfig.groups or [ ]);
    };

  deriveGroups =
    targets:
    foldl' (
      acc: targetId:
      let
        target = targets.${targetId};
      in
      foldl' (
        groupAcc: group:
        groupAcc
        // {
          ${group} = sort builtins.lessThan (
            unique ((if hasAttr group groupAcc then groupAcc.${group} else [ ]) ++ [ target.publicKey ])
          );
        }
      ) acc target.groups
    ) { } (sortedAttrNames targets);

  duplicateAgenixNames =
    selectedSecrets:
    let
      names = map (secret: secret.agenixName) selectedSecrets;
      uniques = unique names;
    in
    filter (name: (builtins.length (filter (candidate: candidate == name) names)) > 1) uniques;

  selectSecretsForTarget =
    { secretsTree, target }:
    let
      canonicalSecrets = flattenSecretsTree secretsTree;
      selectedSecrets = filter (secret: secretAppliesToTarget secret target) (
        map (id: canonicalSecrets.${id}) (sortedAttrNames canonicalSecrets)
      );
      duplicateNames = duplicateAgenixNames selectedSecrets;
    in
    if duplicateNames != [ ] then
      mkKeyError (
        "target ${target.targetId} resolves duplicate agenix names: " + concatStringsSep ", " duplicateNames
      )
    else
      listToAttrs (
        map (secret: nameValuePair secret.agenixName { inherit (secret) file; }) selectedSecrets
      );

  recipientsForTarget =
    groups: target:
    sort builtins.lessThan (
      unique ([ target.publicKey ] ++ concatLists (map (group: groups.${group} or [ ]) target.groups))
    );

  mkTargets =
    { homeConfigs, hostConfigs }:
    let
      secretEnabledHomes = filterAttrs (
        _: configData: hasAttrByPath [ "secrets" ] configData
      ) homeConfigs;
      secretEnabledNixos = filterAttrs (
        _: configData: hasAttrByPath [ "secrets" ] configData
      ) hostConfigs.nixos;
      secretEnabledDarwin = filterAttrs (
        _: configData: hasAttrByPath [ "secrets" ] configData
      ) hostConfigs.darwin;

      homeTargets = listToAttrs (
        mapAttrsToList (
          name: configData:
          nameValuePair "home:${name}" (normalizeTarget {
            targetId = "home:${name}";
            targetType = "home";
            inherit configData;
          })
        ) secretEnabledHomes
      );

      nixosTargets = listToAttrs (
        mapAttrsToList (
          name: configData:
          nameValuePair "host:nixos:${name}" (normalizeTarget {
            targetId = "host:nixos:${name}";
            targetType = "host";
            configData = configData // {
              secretPlatform = "nixos";
            };
          })
        ) secretEnabledNixos
      );

      darwinTargets = listToAttrs (
        mapAttrsToList (
          name: configData:
          nameValuePair "host:darwin:${name}" (normalizeTarget {
            targetId = "host:darwin:${name}";
            targetType = "host";
            configData = configData // {
              secretPlatform = "darwin";
            };
          })
        ) secretEnabledDarwin
      );
    in
    homeTargets // nixosTargets // darwinTargets;

  mkSecretctlIndex =
    {
      secretsTree,
      homeConfigs,
      hostConfigs,
    }:
    let
      canonicalSecrets = flattenSecretsTree secretsTree;
      targets = mkTargets { inherit homeConfigs hostConfigs; };
      derivedGroups = deriveGroups targets;

      consumersFor =
        secret:
        sort builtins.lessThan (
          filter (targetId: secretAppliesToTarget secret targets.${targetId}) (sortedAttrNames targets)
        );

      recipientsFor =
        consumerIds:
        sort builtins.lessThan (unique (map (targetId: targets.${targetId}.publicKey) consumerIds));

      indexSecrets = listToAttrs (
        map (
          secretId:
          let
            secret = canonicalSecrets.${secretId};
            consumers = consumersFor secret;
          in
          nameValuePair secretId {
            id = secretId;
            inherit (secret) group;
            inherit (secret) scope;
            inherit (secret) selector;
            inherit (secret) agenixName;
            file = secret.fileRel;
            recipients = recipientsFor consumers;
            inherit consumers;
          }
        ) (sortedAttrNames canonicalSecrets)
      );
    in
    {
      version = 1;
      groups = derivedGroups;
      targets = listToAttrs (
        map (
          targetId:
          let
            target = targets.${targetId};
          in
          nameValuePair targetId {
            type = target.targetType;
            inherit (target) groups;
            inherit (target) publicKey;
            recipients = recipientsForTarget derivedGroups target;
          }
        ) (sortedAttrNames targets)
      );
      secrets = indexSecrets;
    };
in
{
  inherit flattenSecretsTree mkSecretctlIndex selectSecretsForTarget;
}
