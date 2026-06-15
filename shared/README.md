# shared/

Cross-platform assets that all apps consume:
- Design tokens (colors, spacing, radii)
- Icon source files
- Copy / strings (when we internationalize)
- Brand kit

Stuff in here should be platform-agnostic (no Swift, no C#, no Rust). Each platform app converts these into their native format at build time.
