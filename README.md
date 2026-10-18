# Smart Dialer

Flutter dialer: keypad, recents, incoming call screen (Accept / Reject / Answer with AI).
Unknown numbers are answered by the AI automatically; saved contacts get 3 buttons.

## Option 1: Apne computer par (Flutter installed ho)
    flutter create --platforms=android,web .     # ek baar, android/ aur web/ folder banata hai
    flutter pub get
    flutter run -d chrome                         # browser mein interface dekho
    flutter build apk --release                   # APK: build/app/outputs/flutter-apk/app-release.apk
    flutter build web --release                   # web page: build/web/

## Option 2: Bina Flutter install kiye (GitHub Actions)
1. GitHub par naya repo banao, is folder ki saari files upload/push karo (branch: main).
2. Repo > Actions tab > "Build APK and Web" ka run khatam hone do (5-8 min).
3. Run ke andar "Artifacts" se `smart-dialer-apk` download karo, phone mein install karo.
4. Web preview: Settings > Pages > Source: "Deploy from a branch" > branch `gh-pages` / root.
   Link: https://<username>.github.io/<repo-name>/

## Quick look, bina kisi setup ke
dartpad.dev kholo, Flutter mode, `lib/main.dart` ka code paste karo, Run.
