# devstrap

Siapin laptop buat ngoding Flutter dalam satu perintah. Idenya sederhana: yang disimpan di repo ini cuma daftar apa yang aku butuhin, terus script-nya yang ngecek OS-nya apa dan install pakai cara yang sesuai

Sekarang baru jalan di **Ubuntu 26.04**. OS lain nyusul

## Pakai

Ubuntu fresh belum ada `curl`, jadi pakai `wget`:

```bash
wget -qO- https://raw.githubusercontent.com/theodorusyoga/devstrap/main/install.sh | bash
```

Kalau `curl` udah ada:

```bash
curl -fsSL https://raw.githubusercontent.com/theodorusyoga/devstrap/main/install.sh | bash
```

Jangan pakai `sudo` di depannya, nanti script-nya minta password sendiri pas perlu

**Baca dulu script-nya sebelum dijalanin.** Perintah di atas download script dari internet terus langsung dijalanin. Itu wajar buat repo yang kamu percaya, tapi tetep cek dulu isinya

### Mau lihat dulu tanpa install apa-apa

```bash
wget -qO- https://raw.githubusercontent.com/theodorusyoga/devstrap/main/install.sh | DEVSTRAP_DRY_RUN=1 bash
```

## Yang diinstall di Ubuntu

| Tool | Lewat |
|---|---|
| git, curl, wget, unzip, zip, xz-utils | apt |
| scrcpy | apt |
| VS Code | snap |
| Android Studio | snap |
| Google Chrome | .deb resmi dari Google (amd64) |
| Claude Desktop (beta) | apt repo resmi Anthropic |
| FVM + Flutter stable | installer resmi FVM |

Aman dijalanin berkali-kali. Yang udah ke-install bakal dilewati

## Yang gak ikut, karena cuma ada di macOS

- **CocoaPods** dan **Ruby 3.2** buat CocoaPods: cuma kepake buat build iOS, dan build iOS butuh Xcode yang cuma ada di Mac
- **`flutter precache --ios`**: alasan yang sama, diganti `--android`
- **Sourcetree**: gak ada versi Linux
- **Homebrew**: sebenernya bisa jalan di Linux, tapi semua aplikasi di atas udah ada lewat apt dan snap, jadi gak perlu package manager kedua

## Habis install

1. Tutup terus buka lagi terminal biar `fvm` dan `flutter` kebaca
2. Buka Android Studio sekali buat download Android SDK
3. Jalanin `flutter doctor`

## Struktur

```
install.sh              cek OS, ambil repo, lempar ke script OS yang cocok
os/ubuntu.sh            cara install di Ubuntu
packages/ubuntu/        daftar paket apt dan snap
```

Nambah tool cukup tambah satu baris di `packages/ubuntu/apt.txt` atau `snap.txt`. Nambah OS baru cukup bikin `os/<id>.sh`, dengan `<id>` sesuai `ID` di `/etc/os-release`

## Rencana

- **macOS**: Homebrew, CocoaPods, FVM, Android Studio, Sourcetree, VS Code, Chrome, scrcpy
- **Fedora**: catatan aja, Claude Desktop belum ada versi resmi buat Fedora
