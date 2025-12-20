import 'dart:typed_data';

import 'package:quiver/collection.dart' as collections;
import 'package:quiver/core.dart';

import '../ref_entities/epub_book_ref.dart';
import 'epub_chapter.dart';
import 'epub_content.dart';
import 'epub_schema.dart';
import 'epub_toc.dart';

class EpubBook {
  String? Title;
  String? Author;
  List<String?>? AuthorList;
  EpubSchema? Schema;
  EpubContent? Content;
  Uint8List? CoverImage;
  List<EpubChapter>? Chapters;
  Map<String, int>? PageToChapterMap;
  TableOfContents? Toc;
  EpubBookRef? ref;

  @override
  int get hashCode {
    var objects = [
      Title.hashCode,
      Author.hashCode,
      Schema.hashCode,
      Content.hashCode,
      CoverImage.hashCode,
      ...AuthorList?.map((author) => author.hashCode) ?? [0],
      ...Chapters?.map((chapter) => chapter.hashCode) ?? [0],
    ];
    return hashObjects(objects);
  }

  @override
  bool operator ==(other) {
    if (!(other is EpubBook)) {
      return false;
    }

    return Title == other.Title &&
        Author == other.Author &&
        collections.listsEqual(AuthorList, other.AuthorList) &&
        Schema == other.Schema &&
        Content == other.Content &&
        collections.listsEqual(CoverImage!, other.CoverImage!) &&
        collections.listsEqual(Chapters, other.Chapters);
  }
}
