# Bundled Noto fonts

These fonts are pinned from `google/fonts` commit
`ec626514f79f831f1ab848a82114a0ce7e2d6372` and licensed under the SIL Open
Font License 1.1. `SHA256SUMS` is verified by the iOS build before the files are
copied into Matplotlib's font directory.

The upstream variable fonts were instantiated at their regular defaults
(`wght=400`, `wdth=100` where present) with FontTools 4.63.0. Static instances
avoid Matplotlib classifying the variable fonts as their Thin named instance.

The set covers the scripts needed by the most widely spoken languages by total
speakers, plus Japanese:

- Noto Sans JP: Japanese, Latin, Cyrillic, and Vietnamese
- Noto Sans SC: Simplified Chinese
- Noto Sans Devanagari: Hindi and other Devanagari languages
- Noto Sans Arabic: Arabic-script languages
- Noto Nastaliq Urdu: Urdu's preferred Nastaliq style
- Noto Sans Bengali: Bengali

Source: <https://github.com/google/fonts/tree/ec626514f79f831f1ab848a82114a0ce7e2d6372/ofl>
