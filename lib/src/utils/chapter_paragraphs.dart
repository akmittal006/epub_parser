import 'package:html/dom.dart' as dom;

/// Reduces a chapter's markup to its reader paragraphs, in document order.
///
/// A paragraph is either a block element the chapter wrote (`<p>`, `<h2>`,
/// `<table>`, ...) or a run of inline content - text and inline elements such
/// as `<em>` - that sits directly inside a structural container. Containers
/// (`<div>`, `<section>`, `<article>`) are walked, not kept: the reader points
/// at, plays and stores a paragraph, and a container holds a whole chapter.
///
/// Inside a container a run ends at a `<br>` and at every block boundary.
/// Project Gutenberg writes some books as bare text directly in a `<div>`,
/// one paragraph per `<br/>`; reading only the container's child ELEMENTS
/// kept the `<em>` words and the line breaks and lost every sentence around
/// them. A run keeps its inline markup, so an emphasised word stays inside the
/// sentence it belongs to.
///
/// A container that holds a single run - no `<br>` and no block child - is
/// already one paragraph and is returned as itself.
///
/// An inline element that holds blocks - a link or a `<span>` around whole
/// paragraphs - is walked like a container, and its markup is carried into
/// every paragraph made inside it: `<a href><div>Alpha.</div></a>` becomes
/// `<div><a href>Alpha.</a></div>`. Wrapping it as inline content would nest a
/// block inside a `<p>`, which no HTML parser keeps, so the stored chapter
/// would read back as different paragraphs from the ones it was stored as.
///
/// Elements that are never read - `<script>`, `<style>`, `<template>`,
/// `<noscript>` - contribute nothing, wherever they sit: their source text is
/// not reader text, and it is not something to speak. A paragraph that holds
/// one is returned as a copy without it; the document is never modified.
///
/// The result is a fixed point: the paragraphs re-serialised and run through
/// this again come back the same, which is what lets a stored chapter be
/// re-read into exactly the paragraphs it was stored as.
List<dom.Element> chapterParagraphs(Iterable<dom.Node> nodes) {
  final paragraphs = <dom.Element>[];
  _collect(nodes, paragraphs, const []);
  return paragraphs;
}

/// Structural wrappers walked for their content.
const Set<String> _containerTags = {'div', 'section', 'article'};

/// Elements that end a run of inline content and stand as paragraphs of their
/// own.
const Set<String> _blockTags = {
  'address',
  'aside',
  'blockquote',
  'center',
  'dd',
  'details',
  'dl',
  'dt',
  'fieldset',
  'figcaption',
  'figure',
  'footer',
  'form',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'header',
  'hr',
  'li',
  'main',
  'nav',
  'ol',
  'p',
  'pre',
  'table',
  'ul',
};

/// Elements that are content without carrying any text.
const Set<String> _mediaTags = {
  'audio',
  'embed',
  'iframe',
  'image',
  'img',
  'math',
  'object',
  'picture',
  'svg',
  'video',
};

final String _mediaSelector = _mediaTags.join(',');

final String _blockSelector = {..._containerTags, ..._blockTags}.join(',');

/// Elements whose content is not part of the text.
const Set<String> _nonReadingTags = {'noscript', 'script', 'style', 'template'};

final String _nonReadingSelector = _nonReadingTags.join(',');

/// [wrappers] are the inline elements, outermost first, that the walk is
/// inside of; every paragraph made here carries a copy of them.
void _collect(
  Iterable<dom.Node> nodes,
  List<dom.Element> sink,
  List<dom.Element> wrappers,
) {
  var run = <dom.Node>[];

  void closeRun() {
    if (run.isNotEmpty) {
      final paragraph = _runParagraph(run, wrappers);
      if (_carriesContent(paragraph.nodes)) sink.add(paragraph);
    }
    run = <dom.Node>[];
  }

  for (final node in nodes) {
    if (node is dom.Text) {
      run.add(node);
      continue;
    }
    if (node is! dom.Element) continue;
    final tag = node.localName;
    if (_nonReadingTags.contains(tag)) {
      continue;
    } else if (tag == 'br') {
      closeRun();
    } else if (_containerTags.contains(tag)) {
      closeRun();
      if (!_isSingleRun(node)) {
        _collect(node.nodes, sink, wrappers);
      } else {
        final paragraph = _wrapped(_readable(node), wrappers);
        if (_carriesContent(paragraph.nodes)) sink.add(paragraph);
      }
    } else if (_blockTags.contains(tag)) {
      closeRun();
      sink.add(_wrapped(_readable(node), wrappers));
    } else if (_holdsBlocks(node)) {
      closeRun();
      _collect(node.nodes, sink, [...wrappers, node]);
    } else {
      run.add(node);
    }
  }
  closeRun();
}

bool _isSingleRun(dom.Element container) {
  for (final child in container.children) {
    final tag = child.localName;
    if (tag == 'br' ||
        _containerTags.contains(tag) ||
        _blockTags.contains(tag) ||
        _holdsBlocks(child)) {
      return false;
    }
  }
  return true;
}

bool _carriesContent(Iterable<dom.Node> nodes) {
  for (final node in nodes) {
    if (node is dom.Text) {
      if (node.text.trim().isNotEmpty) return true;
    } else if (node is dom.Element) {
      if (node.text.trim().isNotEmpty) return true;
      if (_mediaTags.contains(node.localName)) return true;
      if (node.querySelector(_mediaSelector) != null) return true;
    }
  }
  return false;
}

/// A run becomes a `<p>` of its own. The nodes are copied, not moved: the
/// document they came from still serialises the chapter's own HTML.
dom.Element _runParagraph(List<dom.Node> run, List<dom.Element> wrappers) {
  final paragraph = dom.Element.tag('p');
  final target = _appendWrappers(paragraph, wrappers);
  for (final node in run) {
    target.append(node.clone(true));
  }
  _removeNonReading(paragraph);
  return paragraph;
}

bool _holdsBlocks(dom.Element element) =>
    element.querySelector(_blockSelector) != null;

/// [block] with the inline [wrappers] moved inside it, around its content.
///
/// Only a block whose content is inline can take them; one that holds blocks
/// of its own, or a table, keeps its structure and goes without.
dom.Element _wrapped(dom.Element block, List<dom.Element> wrappers) {
  if (wrappers.isEmpty ||
      block.nodes.isEmpty ||
      block.localName == 'table' ||
      _holdsBlocks(block)) {
    return block;
  }
  final copy = block.clone(false);
  final target = _appendWrappers(copy, wrappers);
  for (final node in block.nodes) {
    target.append(node.clone(true));
  }
  return copy;
}

/// Appends a copy of each wrapper inside the previous one and returns the
/// innermost. The copies drop `id`: an id names one element, and the wrapper is
/// now repeated.
dom.Element _appendWrappers(dom.Element parent, List<dom.Element> wrappers) {
  var target = parent;
  for (final wrapper in wrappers) {
    final copy = wrapper.clone(false)..attributes.remove('id');
    target.append(copy);
    target = copy;
  }
  return target;
}

/// [element] itself when it holds nothing unread, otherwise a copy without it.
dom.Element _readable(dom.Element element) {
  if (element.querySelector(_nonReadingSelector) == null) return element;
  final copy = element.clone(true);
  _removeNonReading(copy);
  return copy;
}

void _removeNonReading(dom.Element element) {
  for (final unread in element.querySelectorAll(_nonReadingSelector)) {
    unread.remove();
  }
}
