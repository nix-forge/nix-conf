# Research prototype: policy decisions only; no grants, profiles, or activation.
{
  osMajor,
  enrollment ? "personal",
  channel ? "user",
}:
requests:
let
  member = builtins.elem;
  require =
    condition: message: value:
    if condition then value else throw message;
  services = [
    "accessibility"
    "camera"
    "microphone"
    "screen-recording"
    "input-monitoring"
    "full-disk-access"
    "apple-events"
    "local-network"
  ];
  ddmServices = [
    "accessibility"
    "camera"
    "microphone"
    "local-network"
  ];
  managed = member enrollment [
    "user-approved"
    "supervised"
  ];
  decide =
    request:
    let
      inherit (request)
        service
        delivery
        desired
        bundleId
        requirement
        reason
        ;
      enabled = request.enabled or true;
      checked = require (member service services) "Unknown service" (
        require
          (member delivery [
            "consent"
            "pppc"
            "ddm"
          ])
          "Unknown delivery"
          (
            require
              (member desired [
                "allow"
                "deny"
              ])
              "Unknown desired state"
              (
                require
                  (
                    builtins.isString bundleId
                    && bundleId != ""
                    && builtins.isString requirement
                    && requirement != ""
                    && builtins.isString reason
                    && reason != ""
                  )
                  "Identity and feature justification are required"
                  (
                    require (
                      service != "local-network" || osMajor >= 15
                    ) "Local Network requires macOS 15 or later" true
                  )
              )
          )
      );
      policy =
        if delivery == "consent" then
          {
            action = "user-action";
            effect = "instruction-only";
          }
        else if delivery == "ddm" then
          require (osMajor >= 27 && enrollment == "supervised" && channel == "user")
            "DDM privacy defaults require macOS 27, supervision, and user channel"
            (
              require (request.appKit or false) "DDM privacy defaults require AppKit" (
                require (member service ddmServices && desired == "allow") "Unsupported DDM service or deny default"
                  {
                    action = "suggest-default";
                    effect = "requires-user-consent";
                    identifier = "${bundleId} {${requirement}}";
                    organizationJustification = reason;
                  }
              )
            )
        else
          require (managed && channel == "device") "PPPC requires approved MDM and device channel" (
            require (service != "local-network") "PPPC has no Local Network grant" (
              require
                (
                  desired == "deny"
                  || member service [
                    "accessibility"
                    "full-disk-access"
                    "apple-events"
                  ]
                )
                "PPPC cannot silently allow this service"
                {
                  action = "managed-policy";
                  effect =
                    if service == "accessibility" && osMajor >= 27 then "user-changeable-policy" else "managed-policy";
                }
            )
          );
    in
    builtins.deepSeq checked (
      if !enabled then
        [ ]
      else
        [
          (
            policy
            // {
              inherit bundleId service desired;
              observed = "unknown";
            }
          )
        ]
    );
in
require (builtins.isInt osMajor && osMajor >= 13) "Unsupported OS version" (
  require
    (member enrollment [
      "personal"
      "user-approved"
      "supervised"
    ])
    "Unknown enrollment"
    (
      require (member channel [
        "user"
        "device"
      ]) "Unknown channel" (builtins.concatLists (map decide requests))
    )
)
