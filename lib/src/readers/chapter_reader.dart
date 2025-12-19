import 'package:am_epub_parser/src/schema/opf/epub_manifest_item.dart';
import 'package:am_epub_parser/src/schema/opf/epub_version.dart';

import '../ref_entities/epub_book_ref.dart';
import '../ref_entities/epub_chapter_ref.dart';
import '../ref_entities/epub_text_content_file_ref.dart';
import '../schema/navigation/epub_navigation_point.dart';
import '../schema/opf/epub_spine_item_ref.dart';

class ChapterReader {
  static List<EpubChapterRef> getChapters(EpubBookRef bookRef) {
    if (bookRef.Schema!.Navigation == null) {
      return <EpubChapterRef>[];
    }

    return getChaptersImplBySpine(
        bookRef, bookRef.Schema!.Package!.Spine!.Items!);

    if (bookRef.Schema!.Package!.Version == EpubVersion.Epub2) {
      // bookRef.Schema!.Package!.
      return getChaptersImplBySpine(
          bookRef, bookRef.Schema!.Package!.Spine!.Items!);
    } else {
      return getChaptersImpl(
          bookRef, bookRef.Schema!.Navigation!.NavMap!.Points!);
    }
  }

  static List<EpubChapterRef> getChaptersImpl(
      EpubBookRef bookRef, List<EpubNavigationPoint> navigationPoints) {
    var result = <EpubChapterRef>[];
    for (var key in bookRef.Content!.Html!.keys) {
      print("[EPUB V3 DEBUG]" + key);
    }
    navigationPoints.forEach((EpubNavigationPoint navigationPoint) {
      String? contentFileName;
      String? anchor;
      var contentSourceAnchorCharIndex =
          navigationPoint.Content!.Source!.indexOf('#');
      if (contentSourceAnchorCharIndex == -1) {
        contentFileName = navigationPoint.Content!.Source;
        anchor = null;
      } else {
        contentFileName = navigationPoint.Content!.Source!
            .substring(0, contentSourceAnchorCharIndex);
        anchor = navigationPoint.Content!.Source!
            .substring(contentSourceAnchorCharIndex + 1);
      }
      contentFileName = Uri.decodeFull(contentFileName!);
      EpubTextContentFileRef? htmlContentFileRef;

      //print all bookRef.Content!.Html! keys
      print("[EPUB V3 DEBUG] $contentFileName");

      // for (var key in bookRef.Content!.Html!.keys) {
        if (bookRef.Content!.Html!.containsKey(contentFileName)) {
          // contentFileName = key;
          htmlContentFileRef = bookRef.Content!.Html![contentFileName];
          var chapterRef = EpubChapterRef(htmlContentFileRef);
          chapterRef.ContentFileName = contentFileName;
          chapterRef.Anchor = anchor;
          chapterRef.Title = navigationPoint.NavigationLabels!.first.Text;
          chapterRef.SubChapters =
              getChaptersImpl(bookRef, navigationPoint.ChildNavigationPoints!);

          result.add(chapterRef);
          result.addAll(chapterRef.SubChapters as Iterable<EpubChapterRef>);
        //   break;
        // }
      }
    });
    return result;
  }

  static List<EpubChapterRef> getChaptersImplBySpine(
      EpubBookRef bookRef, List<EpubSpineItemRef> spineItemRef) {
    var result = <EpubChapterRef>[];
    spineItemRef.forEach((EpubSpineItemRef spineItemRef) {
      String? contentFileName;
      String? anchor;
      var manifestItem = bookRef.Schema!.Package!.Manifest!.Items!.where((item) => spineItemRef.IdRef == item.Id).first;

      contentFileName = Uri.decodeFull(manifestItem.Href!);
      EpubTextContentFileRef? htmlContentFileRef;
      if (!bookRef.Content!.Html!.containsKey(contentFileName)) {
        throw Exception(
            'Incorrect EPUB manifest: item with href = \"$contentFileName\" is missing.');
      }

      htmlContentFileRef = bookRef.Content!.Html![contentFileName];
      var chapterRef = EpubChapterRef(htmlContentFileRef);
      chapterRef.ContentFileName = contentFileName;
      chapterRef.Anchor = anchor;
      chapterRef.Title = "chap title";
      chapterRef.SubChapters = [];
      // chapterRef.Title = spineItemRef.NavigationLabels!.first.Text;
      // chapterRef.SubChapters =
      //     getChaptersImpl(bookRef, spineItemRef.ChildNavigationPoints!);

      result.add(chapterRef);
    });
    return result;
  }
}
