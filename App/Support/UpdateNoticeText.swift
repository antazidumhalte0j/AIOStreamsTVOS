import Foundation

/**
 * The update notice's words (MainViewController's `offerUpdate`), in the page's language among those
 * the web app has catalogs for (`AppLanguage`), addressing the reader as each catalog does.
 */
struct UpdateNoticeText: Sendable {
    let title: String
    /// The newer version, this one, and where releases are.
    let message: @Sendable (_ newer: String, _ current: String, _ releases: String) -> String
    let viewRelease: String
    let ok: String

    static func text(for language: String) -> UpdateNoticeText { AppLanguage.pick(texts, for: language) }

    private static let texts: [String: UpdateNoticeText] = [
        "en-GB": UpdateNoticeText(
            title: "Update available",
            message: { "AIOStreams for Apple TV \($0) is out; this is \($1). Update it in the app you sideload with, or download it from \($2)." },
            viewRelease: "View This Release",
            ok: "OK"
        ),
        "ar": UpdateNoticeText(
            title: "يتوفر تحديث",
            message: { "صدر AIOStreams for Apple TV \($0)، والإصدار الحالي هو \($1). حدّثه من التطبيق الذي تثبّت به التطبيقات جانبيًا، أو نزّله من \($2)." },
            viewRelease: "عرض هذا الإصدار",
            ok: "حسنًا"
        ),
        "ca": UpdateNoticeText(
            title: "Hi ha una actualització",
            message: { "Ja ha sortit AIOStreams for Apple TV \($0); aquesta és la \($1). Actualitza-la des de l'aplicació amb què la instal·les, o baixa-la de \($2)." },
            viewRelease: "Mostra aquesta versió",
            ok: "D'acord"
        ),
        "de": UpdateNoticeText(
            title: "Update verfügbar",
            message: { "AIOStreams for Apple TV \($0) ist erschienen; diese Version ist \($1). Aktualisiere sie in der App, mit der du sie per Sideload installierst, oder lade sie von \($2) herunter." },
            viewRelease: "Diese Version ansehen",
            ok: "OK"
        ),
        "el": UpdateNoticeText(
            title: "Υπάρχει ενημέρωση",
            message: { "Κυκλοφόρησε το AIOStreams for Apple TV \($0)· αυτή η έκδοση είναι η \($1). Ενημέρωσέ το από την εφαρμογή με την οποία το εγκαθιστάς ή κατέβασέ το από το \($2)." },
            viewRelease: "Προβολή αυτής της έκδοσης",
            ok: "OK"
        ),
        "es": UpdateNoticeText(
            title: "Actualización disponible",
            message: { "Ya está disponible AIOStreams for Apple TV \($0); esta es la \($1). Actualízala desde la app con la que la instalas, o descárgala de \($2)." },
            viewRelease: "Ver esta versión",
            ok: "Aceptar"
        ),
        "fi": UpdateNoticeText(
            title: "Päivitys saatavilla",
            message: { "AIOStreams for Apple TV \($0) on julkaistu; tämä on \($1). Päivitä se sovelluksella, jolla asennat sen, tai lataa se osoitteesta \($2)." },
            viewRelease: "Näytä tämä versio",
            ok: "OK"
        ),
        "fr": UpdateNoticeText(
            title: "Mise à jour disponible",
            message: { "AIOStreams for Apple TV \($0) est disponible ; celle-ci est la \($1). Mettez-la à jour dans l'app avec laquelle vous l'installez, ou téléchargez-la sur \($2)." },
            viewRelease: "Voir cette version",
            ok: "OK"
        ),
        "id": UpdateNoticeText(
            title: "Pembaruan tersedia",
            message: { "AIOStreams for Apple TV \($0) sudah dirilis; versi ini adalah \($1). Perbarui melalui aplikasi yang Anda gunakan untuk memasangnya, atau unduh dari \($2)." },
            viewRelease: "Lihat Rilis Ini",
            ok: "OK"
        ),
        "it": UpdateNoticeText(
            title: "Aggiornamento disponibile",
            message: { "È uscita AIOStreams for Apple TV \($0); questa è la \($1). Aggiornala dall'app con cui la installi, oppure scaricala da \($2)." },
            viewRelease: "Vedi questa versione",
            ok: "OK"
        ),
        "ms": UpdateNoticeText(
            title: "Kemas kini tersedia",
            message: { "AIOStreams for Apple TV \($0) telah dikeluarkan; versi ini ialah \($1). Kemas kininya dalam apl yang anda gunakan untuk memasangnya, atau muat turun dari \($2)." },
            viewRelease: "Lihat Keluaran Ini",
            ok: "OK"
        ),
        "nb": UpdateNoticeText(
            title: "Oppdatering tilgjengelig",
            message: { "AIOStreams for Apple TV \($0) er ute; denne er \($1). Oppdater den i appen du installerer den med, eller last den ned fra \($2)." },
            viewRelease: "Vis denne versjonen",
            ok: "OK"
        ),
        "nl": UpdateNoticeText(
            title: "Update beschikbaar",
            message: { "AIOStreams for Apple TV \($0) is uit; dit is \($1). Werk de app bij in de app waarmee je hem installeert, of download hem van \($2)." },
            viewRelease: "Deze versie bekijken",
            ok: "OK"
        ),
        "pl": UpdateNoticeText(
            title: "Dostępna aktualizacja",
            message: { "Jest już AIOStreams for Apple TV \($0); ta wersja to \($1). Zaktualizuj ją w aplikacji, którą ją instalujesz, lub pobierz ze strony \($2)." },
            viewRelease: "Pokaż tę wersję",
            ok: "OK"
        ),
        "pt": UpdateNoticeText(
            title: "Atualização disponível",
            message: { "Já saiu a AIOStreams for Apple TV \($0); esta é a \($1). Atualize-a na app com que a instala, ou transfira-a de \($2)." },
            viewRelease: "Ver esta versão",
            ok: "OK"
        ),
        "pt-BR": UpdateNoticeText(
            title: "Atualização disponível",
            message: { "Saiu o AIOStreams for Apple TV \($0); esta é a \($1). Atualize pelo app que você usa para instalá-lo, ou baixe em \($2)." },
            viewRelease: "Ver esta versão",
            ok: "OK"
        ),
        "ro": UpdateNoticeText(
            title: "Actualizare disponibilă",
            message: { "A apărut AIOStreams for Apple TV \($0); aceasta este \($1). Actualizeaz-o din aplicația cu care o instalezi sau descarc-o de la \($2)." },
            viewRelease: "Vezi această versiune",
            ok: "OK"
        ),
        "ru": UpdateNoticeText(
            title: "Доступно обновление",
            message: { "Вышла AIOStreams for Apple TV \($0); у вас \($1). Обновите её в приложении, через которое устанавливаете, или скачайте с \($2)." },
            viewRelease: "Открыть этот выпуск",
            ok: "OK"
        ),
        "sl": UpdateNoticeText(
            title: "Na voljo je posodobitev",
            message: { "Izšla je AIOStreams for Apple TV \($0); ta različica je \($1). Posodobite jo v aplikaciji, s katero jo nameščate, ali jo prenesite s \($2)." },
            viewRelease: "Prikaži to izdajo",
            ok: "V redu"
        ),
        "sv": UpdateNoticeText(
            title: "Uppdatering tillgänglig",
            message: { "AIOStreams for Apple TV \($0) har släppts; den här är \($1). Uppdatera den i appen du installerar den med, eller ladda ner den från \($2)." },
            viewRelease: "Visa den här versionen",
            ok: "OK"
        ),
        "tr": UpdateNoticeText(
            title: "Güncelleme var",
            message: { "AIOStreams for Apple TV \($0) çıktı; bu sürüm \($1). Yüklemek için kullandığınız uygulamadan güncelleyin veya \($2) adresinden indirin." },
            viewRelease: "Bu Sürümü Görüntüle",
            ok: "Tamam"
        ),
        "zh-Hans": UpdateNoticeText(
            title: "有可用更新",
            message: { "AIOStreams for Apple TV \($0) 已发布，当前版本为 \($1)。请在你用来安装它的应用中更新，或从 \($2) 下载。" },
            viewRelease: "查看此版本",
            ok: "好"
        ),
    ]
}
