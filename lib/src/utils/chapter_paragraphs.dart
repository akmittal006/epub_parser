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
  _collect(nodes, paragraphs);
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

/// Elements whose content is not part of the text.
const Set<String> _nonReadingTags = {'noscript', 'script', 'style', 'template'};

final String _nonReadingSelector = _nonReadingTags.join(',');

void _collect(Iterable<dom.Node> nodes, List<dom.Element> sink) {
  var run = <dom.Node>[];

  void closeRun() {
    if (run.isNotEmpty) {
      final paragraph = _runParagraph(run);
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
        _collect(node.nodes, sink);
      } else {
        final paragraph = _readable(node);
        if (_carriesContent(paragraph.nodes)) sink.add(paragraph);
      }
    } else if (_blockTags.contains(tag)) {
      closeRun();
      sink.add(_readable(node));
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
        _blockTags.contains(tag)) {
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
dom.Element _runParagraph(List<dom.Node> run) {
  final paragraph = dom.Element.tag('p');
  for (final node in run) {
    paragraph.append(node.clone(true));
  }
  _removeNonReading(paragraph);
  return paragraph;
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
