# macOS için Native MySQL Yönetim Aracı — MVP Planı

## Context

Kullanıcı, SQLyog benzeri (ekran görüntüsünde: sol panelde bağlantı/şema ağacı, üstte Query/History sekmeleri, altta sayfalanabilir Table Data ızgarası) kapsamlı bir MySQL veritabanı yönetim aracını **kendi kullanımı için** macOS'ta native olarak geliştirmek istiyor. Kullanıcının kendi MySQL veritabanları cPanel shared hosting'de (tokay.tr, `cantokay_` prefix'li) barınıyor; bu araç o veritabanlarını (ve genel olarak herhangi bir MySQL sunucusunu) yönetmek için kişisel bir masaüstü aracı olacak. Bu, mevcut `single-line-draw` reposuyla tamamen ilgisiz, sıfırdan yeni bir proje.

Netleştirme turlarında alınan kararlar:
- **Teknoloji:** Native Swift/SwiftUI (Electron/Tauri değil).
- **Konum:** `/Volumes/T9/MySQLMacClient` (boş, harici SSD üzerinde).
- **MVP kapsamı:** minimal tek bağlantı formu + düz tablo listesi + **tablo veri ızgarası** (görüntüleme, hücre düzenleme, satır ekleme/silme, temel filtre/sıralama, sayfalama). Tam şema ağacı, SQL sorgu editörü + geçmiş, ve "Powertools" (yedekleme/senkronizasyon) özellikleri sonraki fazlara bırakılıyor — mimaride yer açılacak ama şimdi inşa edilmeyecek.

Ortam doğrulandı: Xcode 26.1.1 / Swift 6.2.1, macOS 26.5.1. XAMPP kurulu ama MySQL şu an çalışmıyor (geliştirme için başlatılması gerekecek). `vapor/mysql-nio` paketi erişilebilir ve aktif bakımlı (v1.9.1).

## Teknik Kararlar

### 1. Bağlantı katmanı: MySQLNIO (`vapor/mysql-nio`)
libmysqlclient C binding yerine tercih edildi — saf Swift + SwiftNIO, dylib/rpath sorunu yok, dağıtımı kolay. async/await ile `.get()` üzerinden köprüleniyor. Parametreli sorgular ve TLS destekleniyor.

**Bilinen risk (gün 1'de test edilmeli):** MySQL 8'in varsayılan `caching_sha2_password` auth plugin'i ile MySQLNIO'nun uyumu belirsiz olabilir. XAMPP/cPanel kullanıcısı bu plugin'i kullanıyorsa `ALTER USER ... IDENTIFIED WITH mysql_native_password` ile değiştirmek gerekebilir. UI'a geçmeden önce izole bir `swift run` scripti ile bağlantı test edilecek.

Bağlantı pooling'i MVP'de yok — `MySQLService` tek bir `MySQLConnection` + kendi sahip olduğu `EventLoopGroup`'u yönetir (connect'te oluşturulur, disconnect/çıkışta `syncShutdownGracefully()`).

### 2. Veri ızgarası: SwiftUI `Table` (macOS 12+/14 ile olgunlaşmış)
`NSTableView` + `NSViewRepresentable` yerine tercih edildi — dinamik kolon seti (tablo şemasına göre değişen) için çok daha az kod. Hücre düzenleme: her hücre bir `TextField`, `.onSubmit`/focus ile commit — spreadsheet-grade (ok tuşlarıyla gezinme, çoklu hücre kopyala/yapıştır) değil ama MVP için yeterli. Sayfalama zaten LIMIT/OFFSET ile yapıldığından binlerce satır render sorunu olmayacak.

**İleride revize noktası:** Gerçek spreadsheet-grade düzenleme gerekirse `NSTableView`'a geçiş — `TableDataGridView` bu değişimin izole edileceği yer olarak tasarlanacak.

### 3. Proje mimarisi (MVVM)

```
MySQLMacClient/
  Package.swift
  Sources/MySQLMacClient/
    App/MySQLMacClientApp.swift        // @main, WindowGroup
    Models/
      ConnectionProfile.swift          // host, port, user, database, name — Codable, ŞİFRE YOK
      TableInfo.swift
      ColumnInfo.swift                 // name, mysqlType, isNullable, isPrimaryKey, isAutoIncrement, defaultValue
      RowValue.swift                   // MySQLData -> Swift native enum
      TableRow.swift                   // orijinal + düzenlenmiş değerler, dirty-tracking
    Services/
      MySQLService.swift               // EventLoopGroup + MySQLConnection sahibi; connect/disconnect/query/execute
      SchemaIntrospectionService.swift // SHOW TABLES, SHOW COLUMNS, SHOW KEYS (PK tespiti)
      KeychainService.swift            // Security framework ile şifre sakla/oku/sil (connectionId ile keyed)
    Persistence/
      ConnectionStore.swift            // [ConnectionProfile] JSON olarak ~/Library/Application Support/MySQLMacClient/connections.json
    ViewModels/
      ConnectionFormViewModel.swift
      TableListViewModel.swift
      TableDataViewModel.swift         // sayfalama, dirty-cell tracking, PK-aware UPDATE/INSERT/DELETE üretimi
    Views/
      ConnectionFormView.swift
      MainWindowView.swift             // NavigationSplitView: sidebar (tablo listesi) + detail (ızgara)
      TableListView.swift              // MVP'de düz liste
      TableDataGridView.swift          // SwiftUI Table + sayfalama kontrolü
      PaginationControlView.swift      // "Limit rows / First row / # of rows"
      StatusBarView.swift
  Tests/MySQLMacClientTests/
    SchemaIntrospectionServiceTests.swift
    TableDataViewModelTests.swift
```

**Kalıcılık ayrımı:** Şifre → Keychain (`KeychainService`, `SecItemAdd`/`SecItemCopyMatching`/`SecItemUpdate`/`SecItemDelete`, `connectionId` UUID ile keyed). Bağlantı metadata'sı (host/user/db/port/isim) → UserDefaults değil, `~/Library/Application Support/MySQLMacClient/connections.json`.

**Primary key tespiti:** `SHOW KEYS FROM \`table\` WHERE Key_name = 'PRIMARY'` (composite key destekli). PK varsa düzenleme açık; UPDATE/DELETE `WHERE` cümlesi satırın *orijinal* (fetch anındaki) PK değerleriyle kurulur (PK sütunu düzenlenirse bile stale-WHERE hatası olmasın diye). PK yoksa düzenleme kapatılır, ızgarada "Bu tabloda primary key yok, düzenleme kapalı" banner'ı gösterilir — crash yok, sessiz bozulma yok.

**SQL güvenliği:** Filtre değerleri parametreli (`?` binding) geçilir; sütun/tablo isimleri (MySQL parametreli identifier desteklemediği için) `ColumnInfo`'dan alınan whitelist'e karşı doğrulanıp backtick ile escape edilir — ham kullanıcı girdisi asla doğrudan sorguya enjekte edilmez.

**Sayfalama:** `pageSize` (varsayılan 1000), `currentOffset`, `totalRowCount` (ayrı bir `SELECT COUNT(*)` ile, her sayfada tekrar çalıştırılmaz).

### 4. Proje iskeleti: Swift Package Manager tabanlı, `.xcodeproj` değil
Claude Code, Xcode GUI sihirbazını kullanamaz; `.pbxproj`'u elle düzenlemek kırılgan. Bunun yerine:
- Kökte `Package.swift`, `executableTarget` (SwiftUI import eden, `@main App` içeren) — bu gerçek, dock ikonlu, çalıştırılabilir bir `.app` üretir, konsol uygulaması değildir.
- `swift build` / `swift run` ile CLI'dan geliştirme; `xed .` veya `open Package.swift` ile tam Xcode IDE deneyimi (breakpoint, debug dahil) kaybedilmez.
- Bağımlılıklar `Package.swift`'te `.package(url:from:)` ile eklenir.
- Minimum hedef: **macOS 15** — `.macOS(.v15)`. (Uygulama sırasında güncellendi: dinamik kolonlar için kullanılan `TableColumnForEach` gerçekte macOS 14.4 istiyor, SwiftPM'in platform enum'u ise yalnız majör sürümleri ifade ediyor; kullanıcının makinesi zaten 26.5.1 olduğundan geri uyum kısıtı olmadan .v15'e çıkıldı.)
- Gerçek dağıtılabilir `.app` paketleme (Info.plist, ikon) MVP sonrası bir adım.

### 5. Doğrulama Planı (gerçek DB'ye karşı, mock yok)
1. XAMPP MySQL'i başlat (`sudo /Applications/XAMPP/xamppfiles/ctlscript.sh start mysql`) — şu an kapalı.
2. **Auth-plugin riskini önce izole test et**: `mysql -u root -h 127.0.0.1` ile bağlanıp `SELECT plugin FROM mysql.user WHERE User='root';` kontrol et; `caching_sha2_password` ise MySQLNIO ile küçük bir `swift run` scriptiyle bağlantıyı UI'dan önce doğrula.
3. Test şeması oluştur: (a) tek kolonlu PK + karışık tipli (VARCHAR/INT/DATETIME/NULL-able) bir tablo, (b) PK'sız bir tablo (read-only fallback testi için).
4. Bağlantı akışı: formu doldur, connect, yanlış kimlik bilgisi/erişilemeyen host durumunda hata mesajının okunur şekilde göründüğünü doğrula.
5. Tablo listesi akışı: `SHOW TABLES` ile düz listenin dolduğunu doğrula.
6. Izgara akışı: PK'li tabloyu seç, LIMIT/OFFSET'in doğru çalıştığını, bir hücreyi düzenleyip sadece değişen sütun için UPDATE üretildiğini, satır ekleme/silmenin ve temel sıralama/filtrenin DB'ye gerçekten yansıdığını (optimistic UI'a güvenmeden yeniden sorgulayarak) doğrula.
7. PK'sız tablo: düzenlemenin kapalı olduğunu ve banner'ın göründüğünü, crash olmadığını doğrula.
8. **cPanel notu (sadece belgeleme, özellik değil):** tokay.tr'ye uzaktan bağlanmak için cPanel'de "Remote MySQL" altında geliştirme makinesinin IP'sinin izinli olması gerekebilir; birincil geliştirme döngüsü yerel XAMPP üzerinden yürütülecek.

## Sonraki Fazlar (şimdi inşa edilmeyecek, mimaride yer var)
- Tam şema ağacı (veritabanları > tablolar/view'lar/prosedürler/fonksiyonlar/tetikleyiciler) — `TableListView`/`SchemaIntrospectionService`'in `NavigationSplitView` outline'a doğal genişlemesi.
- SQL sorgu editörü + geçmiş — `MySQLService.query`'yi paylaşan yeni bir `QueryEditorViewModel`/`QueryHistoryStore`.
- Powertools (yedekleme/geri yükleme, şema/veri senkronizasyonu) — muhtemelen `mysqldump` çağırma veya `SHOW CREATE TABLE`/`SELECT` tabanlı export; ayrı bir alt sistem.

## Kritik Dosyalar
- `/Volumes/T9/MySQLMacClient/Package.swift`
- `/Volumes/T9/MySQLMacClient/Sources/MySQLMacClient/Services/MySQLService.swift`
- `/Volumes/T9/MySQLMacClient/Sources/MySQLMacClient/Services/SchemaIntrospectionService.swift`
- `/Volumes/T9/MySQLMacClient/Sources/MySQLMacClient/ViewModels/TableDataViewModel.swift`
- `/Volumes/T9/MySQLMacClient/Sources/MySQLMacClient/Persistence/ConnectionStore.swift`
- `/Volumes/T9/MySQLMacClient/Sources/MySQLMacClient/Services/KeychainService.swift`
