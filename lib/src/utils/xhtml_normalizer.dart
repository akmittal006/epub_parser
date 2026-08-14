// Makes XHTML safe to hand to an HTML parser.
//
// EPUB documents are XHTML, where any element may be written in the
// self-closing form `<a id="x"/>`. The HTML5 tree builder ignores that
// trailing solidus on every element that is not a void element, so
// `<a id="x"/>` opens an anchor that is never closed. Because `a` is a
// formatting element, the adoption agency algorithm then re-creates it after
// the enclosing block ends and wraps everything that follows in a clone of it
// - a Project Gutenberg chapter collapses into one giant anchor, and the
// headings that used to sit between paragraphs disappear inside it.
//
// Writing the end tag out restores the tree the document describes.

/// Elements that have no end tag in HTML; their self-closing form is already
/// what the HTML5 parser produces and must be left alone.
const Set<String> _voidElements = <String>{
  'area',
  'base',
  'basefont',
  'bgsound',
  'br',
  'col',
  'embed',
  'frame',
  'hr',
  'img',
  'input',
  'keygen',
  'link',
  'meta',
  'param',
  'source',
  'track',
  'wbr',
};

/// A self-closing start tag, with quoted attribute values kept intact so that
/// a `/>` inside an attribute never ends the match early.
final RegExp _selfClosingTag =
    RegExp('''<([a-zA-Z][a-zA-Z0-9:._-]*)((?:"[^"]*"|'[^']*'|[^"'<>])*?)/>''');

/// Rewrites `<tag …/>` as `<tag …></tag>` for every non-void element.
///
/// Foreign content (SVG, MathML) honours both forms, so rewriting there leaves
/// the tree unchanged.
String normalizeSelfClosingTags(String html) {
  return html.replaceAllMapped(_selfClosingTag, (match) {
    var name = match[1]!;
    if (_voidElements.contains(name.toLowerCase())) return match[0]!;
    return '<$name${match[2]}></$name>';
  });
}
