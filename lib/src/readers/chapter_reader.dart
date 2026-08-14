import '../entities/epub_nav_section.dart';
import '../ref_entities/epub_book_ref.dart';
import '../ref_entities/epub_chapter_ref.dart';
import '../schema/navigation/epub_navigation_point.dart';
import '../schema/opf/epub_spine_item_ref.dart';

class ChapterReader {
  static List<EpubChapterRef> getChapters(EpubBookRef bookRef) {
    if (bookRef.Schema!.Navigation == null) {
      return <EpubChapterRef>[];
    }

    return getChaptersImplBySpine(
        bookRef, bookRef.Schema!.Package!.Spine!.Items!);
  }

  /// One chapter reference per spine item, in reading order.
  ///
  /// Each reference also carries the navigation fragments that point inside its
  /// document ([EpubChapterRef.NavSections]) so the reader can split a
  /// multi-chapter document into one chapter per navigation entry.
  static List<EpubChapterRef> getChaptersImplBySpine(
      EpubBookRef bookRef, List<EpubSpineItemRef> spineItemRefs) {
    var navSections =
        _navSectionsByFile(bookRef.Schema!.Navigation!.NavMap?.Points);
    var result = <EpubChapterRef>[];
    for (var spineItemRef in spineItemRefs) {
      var manifestItem = bookRef.Schema!.Package!.Manifest!.Items!
          .where((item) => spineItemRef.IdRef == item.Id)
          .first;
      var contentFileName = Uri.decodeFull(manifestItem.Href!);
      if (!bookRef.Content!.Html!.containsKey(contentFileName)) {
        throw Exception(
            'Incorrect EPUB manifest: item with href = "$contentFileName" is missing.');
      }

      var chapterRef = EpubChapterRef(bookRef.Content!.Html![contentFileName]);
      chapterRef.ContentFileName = contentFileName;
      chapterRef.Anchor = null;
      chapterRef.Title = null;
      chapterRef.SubChapters = <EpubChapterRef>[];
      chapterRef.NavSections =
          navSections[contentFileName] ?? const <EpubNavSection>[];
      result.add(chapterRef);
    }
    return result;
  }

  /// Navigation fragments grouped by the document they point into.
  static Map<String, List<EpubNavSection>> _navSectionsByFile(
      List<EpubNavigationPoint>? points) {
    var result = <String, List<EpubNavSection>>{};
    _collectNavSections(points, result);
    return result;
  }

  static void _collectNavSections(List<EpubNavigationPoint>? points,
      Map<String, List<EpubNavSection>> sink) {
    if (points == null) return;
    for (var point in points) {
      var source = point.Content?.Source;
      var labels = point.NavigationLabels;
      if (source != null && labels != null && labels.isNotEmpty) {
        var label = labels.first.Text;
        var anchorCharIndex = source.indexOf('#');
        if (label != null && anchorCharIndex >= 0) {
          var fileName = Uri.decodeFull(source.substring(0, anchorCharIndex));
          var anchor = source.substring(anchorCharIndex + 1);
          if (anchor.isNotEmpty) {
            sink
                .putIfAbsent(fileName, () => <EpubNavSection>[])
                .add(EpubNavSection(anchor: anchor, label: label));
          }
        }
      }
      _collectNavSections(point.ChildNavigationPoints, sink);
    }
  }
}
