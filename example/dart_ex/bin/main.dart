import 'dart:io' as io;

import 'package:path/path.dart' as path;
import 'package:epub_parser/epub_parser.dart';
// import 'package:epub_parser/epubx.dart';

main(List<String> args) async {
  //Get the epub into memory somehow
  String fileName = "bin/Crouch, Blake - Dark Matter 2.epub";
  // String fileName = "effectivekotlin.epub";
  String fullPath = path.join(io.Directory.current.path, fileName);
  var targetFile = new io.File(fullPath);
  List<int> bytes = await targetFile.readAsBytes();

// Opens a book and reads all of its content into the memory
  EpubBook epubBook = await EpubReader.readBook(bytes);

// COMMON PROPERTIES

// Book's title
  String? title = epubBook.Title;
  print('Title: $title');

// Book's authors (comma separated list)
  String? author = epubBook.Author;
  print('Author: $author');

// Book's authors (list of authors names)
  List<String?>? authors = epubBook.AuthorList;
  print('Authors: $authors');

// Book's cover image (null if there is no cover)
  var coverImage = epubBook.CoverImage;
  print('Cover image: ${coverImage != null}\n');

// CHAPTERS

// Enumerating chapters
  epubBook.Chapters!.forEach((EpubChapter chapter) {
    // Title of chapter
    String chapterTitle = chapter.Title!;
    print('Chapter title: $chapterTitle');

    // HTML content of current chapter
    String chapterHtmlContent = chapter.HtmlContent!;

    // Nested chapters
    List<EpubChapter> subChapters = chapter.SubChapters!;
  });

// CONTENT

// Book's content (HTML files, stlylesheets, images, fonts, etc.)
  EpubContent bookContent = epubBook.Content!;
  print('Content: ${bookContent.AllFiles?.length} files');

// IMAGES

// All images in the book (file name is the key)
  Map<String, EpubByteContentFile> images = bookContent.Images!;
  print('All images in the book: ${images.length}');

  EpubByteContentFile? firstImage =
      images.isNotEmpty ? images.values.first : null;
  print('First image: ${firstImage != null}');

// Content type (e.g. EpubContentType.IMAGE_JPEG, EpubContentType.IMAGE_PNG)
  EpubContentType contentType = firstImage!.ContentType!;
  print('Content type: $contentType');

// MIME type (e.g. "image/jpeg", "image/png")
  String mimeContentType = firstImage.ContentMimeType!;
  print('MIME type: $mimeContentType');

// HTML & CSS

// All XHTML files in the book (file name is the key)
  Map<String?, EpubTextContentFile> htmlFiles = bookContent.Html!;

// All CSS files in the book (file name is the key)
  Map<String, EpubTextContentFile> cssFiles = bookContent.Css!;

// Entire HTML content of the book
  htmlFiles.values.forEach((EpubTextContentFile htmlFile) {
    String htmlContent = htmlFile.Content!;
  });

// All CSS content in the book
  cssFiles.values.forEach((EpubTextContentFile cssFile) {
    String cssContent = cssFile.Content!;
  });

// OTHER CONTENT

// All fonts in the book (file name is the key)
  Map<String, EpubByteContentFile> fonts = bookContent.Fonts!;
  print('All fonts in the book: ${fonts.length}');

// All files in the book (including HTML, CSS, images, fonts, and other types of files)
  Map<String, EpubContentFile> allFiles = bookContent.AllFiles!;

// ACCESSING RAW SCHEMA INFORMATION

// EPUB OPF data
  EpubPackage package = epubBook.Schema!.Package!;

// Enumerating book's contributors
  package.Metadata!.Contributors!.forEach((contributor) {
    String contributorName = contributor.Contributor!;
    String contributorRole = contributor.Role!;
  });

// EPUB NCX data
  EpubNavigation navigation = epubBook.Schema!.Navigation!;

// Enumerating NCX metadata
  navigation.Head?.Metadata?.forEach((meta) {
    String metadataItemName = meta.Name!;
    String metadataItemContent = meta.Content!;
  });

  // Write the Book
  var written = EpubWriter.writeBook(epubBook);
  // Read the book into a new object!
  var newBook = await EpubReader.readBook(written!);
}
