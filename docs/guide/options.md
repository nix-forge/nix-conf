# Module option reference

The guide build generates this reference from the selected modules through
`nixosOptionsDoc`. It includes types, descriptions, defaults and declarations.
Build `.#feature-options` for the corresponding JSON. The current bounded set
covers Secure Boot preparation, libvirt workstation interfaces, application
recovery recipes and desktop-local service/backup health.

A declared default does not establish that a host selected the feature, that its
external prerequisites exist, or that it passed a native test. Use the
[feature catalog](features.md) and [support table](support.md) together.

<!-- generated-option-reference -->
