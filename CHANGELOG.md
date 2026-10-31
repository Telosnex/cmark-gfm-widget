## 0.2.0

- **Breaking:** `CmarkThemeData.blockSpacing` and
  `CmarkThemeData.listItemBlockSpacing` are now `double`, not `EdgeInsets`.
  The value is the vertical space between two sibling blocks.
- Fix: a block no longer adds space after itself. A single block, and the
  last block of a document, quote, list item or footnote, now ends at its
  content. The same applies to `listItemSpacing` in loose lists.
- Add `CmarkBlockColumn`. It lays out the blocks from `RenderPipeline.render`
  with `blockSpacing` between them. Use it in place of a plain `Column`.
- Hidden footnote definitions (`renderFootnoteDefinitions: false`) now give
  no block, so they add no spacing.

## 0.1.0

- First release on pub.dev: a Flutter renderer for GitHub Flavored
  Markdown, powered by cmark_gfm_dart.
