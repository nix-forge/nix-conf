# Workstation configuration

The shared language for configuring a workstation and its user environment.

## Language

**Host**: A workstation with an operating-system configuration and attached user
environments. A host and a home profile have separate responsibilities.
_Avoid_: using "profile" to mean the whole machine.

**Home profile**: A selected user environment, including applications, shell
behavior, and desktop preferences. It can be attached to a host; only profiles
that support independent use are standalone.
_Avoid_: using "user" to mean the entire configuration of that user's environment.

**Reusable feature**: A capability that a host or home profile can select without
owning its implementation. Multiple targets can select the same feature.
_Avoid_: "host setting" for behavior shared by multiple targets.

**Local configuration**: Settings specific to one host or home profile. "Local"
describes their scope, not their privacy or whether they are committed.
_Avoid_: "private configuration" as a synonym.

**Bootstrap profile**: A reduced user environment intended for initial access or
recovery. It is distinct from the complete workstation environment.
_Avoid_: "desktop profile" when only recovery capabilities are intended.

**Sealed secret**: An encrypted value delivered to authorized consumers under the
repository's secret policy. Its public identifier is distinct from its plaintext.
_Avoid_: treating a secret identifier or public recipient as the secret value.

**Evaluation**: Resolving configuration into the outputs to be built. It does not
establish that those outputs can be built or activated successfully.

**Build**: Producing a configuration's required artifacts. A successful build
alone does not establish the state of the running workstation.

**Activation**: Applying a built configuration to the live system or user
environment. It can change running services and user-visible behavior.
