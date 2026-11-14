# Run: nix-instantiate --eval --strict --json check.nix
let
  planner = import ./plan.nix;
  base = {
    bundleId = "org.example.App";
    requirement = "identifier org.example.App and anchor apple generic";
    reason = "Connect to a selected local service";
    service = "local-network";
    delivery = "consent";
    desired = "allow";
  };
  personal = planner { osMajor = 27; };
  pppc = planner {
    osMajor = 27;
    enrollment = "user-approved";
    channel = "device";
  };
  ddm = planner {
    osMajor = 27;
    enrollment = "supervised";
  };
  force = value: builtins.deepSeq value value;
  rejects = value: !(builtins.tryEval (force value)).success;
  inherit (builtins) head;
  results = {
    personal-consent = (head (personal [ base ])).action == "user-action";
    never-infer-grant = (head (personal [ base ])).observed == "unknown";
    disabled-app = personal [ (base // { enabled = false; }) ] == [ ];
    no-bare-identity = rejects (personal [ (base // { requirement = ""; }) ]);
    no-empty-bundle = rejects (personal [ (base // { bundleId = ""; }) ]);
    no-unjustified-permission = rejects (personal [ (base // { reason = ""; }) ]);
    no-unknown-service = rejects (personal [ (base // { service = "invented"; }) ]);
    no-unknown-delivery = rejects (personal [ (base // { delivery = "silent"; }) ]);
    no-unknown-desired = rejects (personal [ (base // { desired = "maybe"; }) ]);
    no-unknown-enrollment = rejects (
      planner {
        osMajor = 27;
        enrollment = "invented";
      } [ base ]
    );
    no-pre15-local-network = rejects (planner { osMajor = 14; } [ base ]);
    no-personal-pppc = rejects (personal [
      (
        base
        // {
          service = "full-disk-access";
          delivery = "pppc";
        }
      )
    ]);
    no-user-channel-pppc = rejects (
      planner
        {
          osMajor = 27;
          enrollment = "user-approved";
        }
        [
          (
            base
            // {
              service = "full-disk-access";
              delivery = "pppc";
            }
          )
        ]
    );
    no-pppc-local-network = rejects (pppc [ (base // { delivery = "pppc"; }) ]);
    no-pppc-camera-grant = rejects (pppc [
      (
        base
        // {
          service = "camera";
          delivery = "pppc";
        }
      )
    ]);
    no-pppc-mic-grant = rejects (pppc [
      (
        base
        // {
          service = "microphone";
          delivery = "pppc";
        }
      )
    ]);
    no-pppc-screen-grant = rejects (pppc [
      (
        base
        // {
          service = "screen-recording";
          delivery = "pppc";
        }
      )
    ]);
    no-pppc-input-grant = rejects (pppc [
      (
        base
        // {
          service = "input-monitoring";
          delivery = "pppc";
        }
      )
    ]);
    pppc-fda =
      (head (pppc [
        (
          base
          // {
            service = "full-disk-access";
            delivery = "pppc";
          }
        )
      ])).action == "managed-policy";
    pppc-screen-deny =
      (head (pppc [
        (
          base
          // {
            service = "screen-recording";
            delivery = "pppc";
            desired = "deny";
          }
        )
      ])).effect == "managed-policy";
    accessibility27-user-changeable =
      (head (pppc [
        (
          base
          // {
            service = "accessibility";
            delivery = "pppc";
          }
        )
      ])).effect == "user-changeable-policy";
    ddm-consent-still-required =
      (head (ddm [
        (
          base
          // {
            delivery = "ddm";
            appKit = true;
          }
        )
      ])).effect == "requires-user-consent";
    ddm-composed-identity =
      (head (ddm [
        (
          base
          // {
            delivery = "ddm";
            appKit = true;
          }
        )
      ])).identifier == "${base.bundleId} {${base.requirement}}";
    ddm-never-infer-grant =
      (head (ddm [
        (
          base
          // {
            delivery = "ddm";
            appKit = true;
          }
        )
      ])).observed == "unknown";
    no-ddm-deny = rejects (ddm [
      (
        base
        // {
          delivery = "ddm";
          appKit = true;
          desired = "deny";
        }
      )
    ]);
    no-ddm-screen = rejects (ddm [
      (
        base
        // {
          delivery = "ddm";
          appKit = true;
          service = "screen-recording";
        }
      )
    ]);
    no-ddm-non-appkit = rejects (ddm [
      (
        base
        // {
          delivery = "ddm";
          appKit = false;
        }
      )
    ]);
    no-ddm-pre27 = rejects (
      planner
        {
          osMajor = 26;
          enrollment = "supervised";
        }
        [
          (
            base
            // {
              delivery = "ddm";
              appKit = true;
            }
          )
        ]
    );
    no-ddm-unsupervised = rejects (personal [
      (
        base
        // {
          delivery = "ddm";
          appKit = true;
        }
      )
    ]);
    no-ddm-device-channel = rejects (
      planner
        {
          osMajor = 27;
          enrollment = "supervised";
          channel = "device";
        }
        [
          (
            base
            // {
              delivery = "ddm";
              appKit = true;
            }
          )
        ]
    );
  };
in
assert builtins.all (value: value) (builtins.attrValues results);
results
