import '../../../data/models/work_item.dart';
import '../../work_items/form/controls/attachments_section.dart';
import 'attachment_links.dart';
import 'inline_attachments.dart';

/// Adapts the form's [AttachmentSource] to what a Markdown body needs.
///
/// One function rather than a closure at each of the four call sites (the
/// work item Discussion, the pull request description, a thread card and a
/// diff thread), and the one place that knows an inline image must open
/// exactly the way an attachment row does: [openAttachment] pushes the
/// lightbox on the root navigator for an image and the share sheet for
/// anything else (decision T9).
InlineAttachments inlineAttachmentsOf(AttachmentSource source) =>
    InlineAttachments(
      headers: source.headers,
      onOpen: (context, url, name) => openAttachment(
        context,
        info: inlineAttachmentInfo(url),
        source: source,
      ),
    );

/// An [AttachmentInfo] for a URL that came out of a comment body rather than
/// off a relation.
///
/// The synthetic relation is only a carrier for the URL and the name —
/// nothing removes it, and it is never written back. The id matters though:
/// it is what keys the on-disk byte cache, so only a work item attachment
/// (whose GUID is globally unique) gets one. A pull request attachment is
/// keyed by its file name inside one pull request, so two pull requests with
/// an `image.png` would otherwise share a cache entry; leaving the id null
/// keeps it in the by-URL memory cache alone.
AttachmentInfo inlineAttachmentInfo(String url) {
  final name = attachmentFileName(url);
  return AttachmentInfo(
    relation: WorkItemRelation(
      rel: WorkItemRelation.attachedFileRel,
      url: url,
      attributes: {'name': name},
    ),
    name: name,
    url: url,
    id: witAttachmentId(url),
  );
}
