# QuickChat

Option+Space ile açılan, içerik uzadıkça yukarı doğru büyüyen bağımsız bir macOS sohbet penceresi.

## Homebrew ile kurulum

macOS 13 veya üzeri gerekir. Paket Intel ve Apple Silicon yürütülebilirlerini içerir.

```sh
brew install --cask frknakbl/tap/quickchat
```

Kurulumdan sonra Uygulamalar klasöründen QuickChat’i açın ve ChatGPT hesabınızla giriş yapın.
Önceden elle kurduğunuz bir QuickChat varsa, Homebrew kurulumundan önce uygulamayı kapatıp
mevcut `.app` kopyasını Çöp Sepeti’ne taşıyın. Normal kaldırma hesap oturumunuzu silmez.

## İlk açılış

Bu sürüm bir önizlemedir. Yerel bütünlük imzası taşır, Apple Developer ID imzası ve noter onayı yoktur.
macOS ilk açılışı engelleyebilir. [Apple’ın açıklamasını](https://support.apple.com/en-us/102445) okuyun;
yalnız kaynağına güvendiğiniz ve bütünlüğünü doğruladığınız uygulamayı açın.
Homebrew tanımı sistemin güvenlik kontrollerini değiştirmez.

macOS 13 hedefiyle derleme ve iki mimarinin paket kontrolü yapılmıştır. Çalışan uygulama
Apple Silicon üzerinde macOS 27’de denenmiştir; Intel ve eski macOS sürümlerinde canlı test yapılmamıştır.

## Kullanım

- `Option+Space`: pencereyi göster / gizle.
- Yanıt uzadıkça alt kenar sabit kalır, pencere animasyonla yukarı büyür. Üst sınır 820 nokta veya ekranın üst sınırıdır.
- Yeni sohbet 420 noktalık kompakt yüksekliğe döner; genişlik korunur.
- `⌘N`: yeni sohbet. `⌘O`: kuruluysa ana ChatGPT uygulamasını aç.
- `⌘C`, `⌘V`, `⌘X`, `⌘A`, `⌘Z`, `⇧⌘Z`: standart metin komutları.
- `Escape`: pencereyi gizle. Gizli olarak beş dakika bekledikten sonraki açılış yeni sohbet başlatır.

Uygulama ChatGPT’nin web arayüzünü kullanır. API anahtarı gerekmez; internet bağlantısı ve ChatGPT hesabı gerekir.
QuickChat, OpenAI’ın resmî uygulaması değildir.

## Güncelleme ve kaldırma

```sh
brew update
brew upgrade --cask frknakbl/tap/quickchat
```

```sh
brew uninstall --cask frknakbl/tap/quickchat
```

## Doğrudan indirme

[GitHub Releases](https://github.com/frknakbl/quickchat-app/releases) sayfasından
`QuickChat-<sürüm>-universal.zip` ile yanındaki `.sha256` dosyasını indirin.
İki dosyanın bulunduğu klasörde SHA-256 kontrolü yapın:

```sh
shasum -a 256 -c QuickChat-2.4.8-universal.zip.sha256
```

ZIP’i açıp QuickChat’i Uygulamalar klasörüne taşıyın.
