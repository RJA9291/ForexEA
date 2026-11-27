## Langkah: UPLOAD — Episode {ep} melalui Uplika (pemilik sudah lulus)

Workspace `{uplika_workspace}`, akaun YouTube `{uplika_youtube_account}`. Sentiasa hantar workspaceId.

1. Upload video `{video}`: `media_presign` → `curl -T` (PUT) ke URL presigned → `media_complete`.
   URL tamat dalam 60 minit; jika upload gagal kerana tamat, presign semula dan cuba lagi.
2. Upload thumbnail `{thumbnail}` dengan cara yang sama.
3. `publish` ke akaun YouTube dengan: title, description, tags dari `{upload_md}`; categoryId 24;
   privacyStatus private; publishAt {publish_date}T09:00:00+08:00; madeForKids false;
   containsSyntheticMedia false; thumbnailMediaId; `wait: true`.
4. Sahkan post berjaya (dapatkan YouTube video id). Jika gagal, `defer` dengan ralat dan berhenti.

Selesai: `python studio/engine.py done youtube-last-shift upload --set last_publish_date={publish_date} last_video_id=<id YouTube>`
