# Java formatter

Drop an Eclipse formatter profile here as `eclipse-formatter.xml` (Eclipse: Preferences >
Java > Code Style > Formatter > Export) to use it for every project that has none of its own.

A project's own `eclipse-formatter.xml`, `formatter.xml` or `.settings/formatter.xml` takes
priority. Files are formatted on save whenever a profile is found (no profile, no format on save).
Format manually with `<leader>Jf`, then restart jdtls with `<leader>JR` after changing the file.
