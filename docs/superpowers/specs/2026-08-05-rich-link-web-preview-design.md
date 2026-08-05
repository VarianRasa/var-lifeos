# Rich Link Web Preview Cards Design Spec

## Overview
Menambahkan fitur Rich Link Web Preview ke canvas mindmap Milanote-style. Ketika pengguna menambah node tipe `link` atau men-drag-drop URL ke canvas, aplikasi akan melakukan fetching metadata (OpenGraph/HTML tags) secara client-side dan merender card pratinjau kaya (thumbnail gambar, favicon, judul, & deskripsi).

## 1. Domain Layer (`lib/features/mindmap/domain/node_type_payloads.dart`)
Memperluas `LinkPayload`:
- `url`: String
- `title`: String
- `description`: String
- `imageUrl`: String
- `faviconUrl`: String
- `siteName`: String
- `isFetched`: bool

## 2. Application Layer (`lib/features/mindmap/application/link_metadata_fetcher_service.dart`)
Service untuk scraping OpenGraph tags HTML tanpa dependensi eksternal berat:
- Menggunakan `http.get()` dengan `User-Agent` browser standar.
- Mem-parse tag meta:
  - Title: `og:title` -> `<title>`
  - Image: `og:image` -> `twitter:image`
  - Description: `og:description` -> `description`
  - Favicon: `<link rel="icon">` -> `/favicon.ico`
- Melakukan update pada data node secara asinkron saat URL baru dimasukkan.

## 3. Presentation Layer (`lib/features/mindmap/presentation/mindmap_canvas.dart`)
Peningkatan visual card `NodeType.link`:
- Thumbnail atas dengan rasio pas (jika ada `imageUrl`).
- Baris metadata: Favicon mini 16x16 + nama domain/site.
- Judul link tebal (maks 2 baris).
- Deskripsi ringkas (maks 2 baris).
- Action button untuk membuka URL di browser eksternal via `url_launcher`.
