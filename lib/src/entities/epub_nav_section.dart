/// A navigation entry that addresses a fragment inside a spine document.
///
/// Most EPUBs place one chapter per spine document, so the navigation document
/// points at whole files and the spine already is the chapter list. Project
/// Gutenberg instead packs the whole book into a handful of large documents and
/// addresses each chapter with a fragment (`19476-h-0.htm.xhtml#pgepubid00011`).
/// [EpubNavSection] carries those fragments so the reader can split such a
/// document into one chapter per navigation entry.
class EpubNavSection {
  const EpubNavSection({required this.anchor, required this.label});

  /// The fragment identifier, without the leading `#`.
  final String anchor;

  /// The navigation label shown in a table of contents.
  final String label;
}
