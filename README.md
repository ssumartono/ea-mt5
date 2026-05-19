# TONO Confluence Master XAU (v6.10.4) - Visual Clutter Control

Expert Advisor (EA) MetaTrader 5 yang dirancang khusus untuk pair **XAUUSD (Gold)** pada timeframe **M5** (5 Menit). EA ini mengkombinasikan sinyal *Confluence* (persetujuan antar indikator) dari berbagai indikator teknikal klasik dengan analisa zona *Supply & Demand* untuk mencari area masuk dengan probabilitas tinggi.

## 🚀 Fitur Utama

### 1. Confluence Scoring System (Skor Momentum)
EA menggunakan sistem penilaian (skor maksimal 100 poin) untuk mengevaluasi kekuatan tren dan menentukan apakah sinyal layak untuk di-trade:
- **EMA (34)**: Penentu tren utama harga (28 poin).
- **MACD (8, 21, 9)**: Konfirmasi persilangan arah tren (24 poin).
- **RSI (9)**: Kekuatan momentum atas/bawah garis tengah 50 (18 poin).
- **Stochastic (5, 3, 3)**: Deteksi momentum jangka pendek (16 poin).
- **ADX (10)**: Filter kekuatan tren (memberikan tambahan bonus 14 poin jika tren kuat).

### 2. Supply & Demand (S/D) Otomatis
- **Pendeteksi Zona**: Secara otomatis menggambar zona *Supply* (Resisten) dan *Demand* (Support) menggunakan deteksi *Pivot* dan *Impulse Move* berbasis ATR.
- **Entry Filter**: Mencegah order "konyol" (menabrak tembok pembeli/penjual). Mencegah *BUY* saat harga terlalu dekat dengan zona *Supply*, dan mencegah *SELL* di dekat zona *Demand*.

### 3. Visual Clutter Control & Panel Interaktif
- **Bersih & Rapi**: Anda bebas mematikan blok warna, garis batas, maupun teks di zona S/D jika chart dirasa terlalu ramai.
- **Dasbor On-Chart**: Terdapat panel interaktif yang memonitor skor indikator, status *Spread*, ADX, serta log *debug* posisi zona secara *real-time*.

### 4. Manajemen Risiko
- **Tiga Mode Utama**: 
  - `MODE_SAFE`: Butuh skor minimum 74 dan ADX kuat (22+).
  - `MODE_BALANCED`: Butuh skor minimum 66 dan ADX menengah (18+).
  - `MODE_AGGRESSIVE`: Butuh skor minimum 58 dan ADX rendah (14+).
- **Manajemen Posisi**: Didukung pengaturan SL/TP berbasis poin, sistem **Breakeven** otomatis, serta **Trailing Stop**.
- **Mode Manual/Auto**: Bisa digunakan sepenuhnya untuk eksekusi otomatis (`Inp_Enable_AutoTrade = true`) atau sekadar alat bantu pengingat (*visual only*).

## ⚙️ Cara Penggunaan
1. Pasang file `.mq5` ke dalam folder `MQL5/Experts` pada instalasi MetaTrader 5 Anda.
2. Buka chart **XAUUSD** atau **XAUUSD.m** pada timeframe **M5**.
3. *Attach* EA ke chart.
4. Sesuaikan parameter di bagian *Input*, seperti Mode Risiko (Safe/Balanced/Aggressive), jarak Stop Loss / Take Profit, dan visual yang ingin ditampilkan.
5. Jika ingin EA mengeksekusi *order* otomatis, pastikan tombol *Algo Trading* di MT5 aktif, dan ubah pengaturan `Inp_Enable_AutoTrade` menjadi `true`.
