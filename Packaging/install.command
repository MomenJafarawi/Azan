#!/bin/zsh
# يثبّت برنامج أذان بمجلد التطبيقات ويشيل حظر الأمان ويفتحه
cd "$(dirname "$0")"
echo "جاري تثبيت أذان..."
if [ ! -d "Azan.app" ]; then echo "ما لقيت Azan.app جنب هالملف"; read; exit 1; fi
pkill -x Azan 2>/dev/null
rm -rf /Applications/Azan.app
ditto "Azan.app" /Applications/Azan.app || { echo "ما قدرت أنسخ لمجلد التطبيقات"; read; exit 1; }
xattr -dr com.apple.quarantine /Applications/Azan.app 2>/dev/null
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/Azan.app >/dev/null 2>&1
pluginkit -a /Applications/Azan.app/Contents/PlugIns/AzanWidget.appex 2>/dev/null
open /Applications/Azan.app
echo "تم. أذان شغّال هلأ فوق بشريط القوائم."
sleep 2
