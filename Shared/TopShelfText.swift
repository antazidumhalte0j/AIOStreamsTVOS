import Foundation

/**
 * The Top Shelf's row titles in the page's language (`TopShelfStore.language`), as the web app's own
 * catalogs word its home page's rows ("Continue watching", "Next up"), where they have them.
 */
struct TopShelfText {
    let continueWatching: String
    let nextUp: String

    static func text(for language: String) -> TopShelfText { AppLanguage.pick(texts, for: language) }

    private static let texts: [String: TopShelfText] = [
        "en-GB": TopShelfText(continueWatching: "Continue watching", nextUp: "Next up"),
        "ar": TopShelfText(continueWatching: "متابعة المشاهدة", nextUp: "التالي"),
        "ca": TopShelfText(continueWatching: "Continua mirant", nextUp: "A continuació"),
        "de": TopShelfText(continueWatching: "Weiterschauen", nextUp: "Als Nächstes"),
        "el": TopShelfText(continueWatching: "Συνέχεια παρακολούθησης", nextUp: "Επόμενα επεισόδια"),
        "es": TopShelfText(continueWatching: "Seguir viendo", nextUp: "A continuación"),
        "fi": TopShelfText(continueWatching: "Jatka katsomista", nextUp: "Seuraavaksi"),
        "fr": TopShelfText(continueWatching: "Reprendre la lecture", nextUp: "À suivre"),
        "he": TopShelfText(continueWatching: "המשך צפייה", nextUp: "הבאים בתור"),
        "id": TopShelfText(continueWatching: "Lanjutkan menonton", nextUp: "Berikutnya ditonton"),
        "it": TopShelfText(continueWatching: "Continua a guardare", nextUp: "In arrivo"),
        "ms": TopShelfText(continueWatching: "Teruskan menonton", nextUp: "Seterusnya"),
        "nb": TopShelfText(continueWatching: "Fortsett å se", nextUp: "Neste"),
        "nl": TopShelfText(continueWatching: "Verder kijken", nextUp: "Volgende"),
        "pl": TopShelfText(continueWatching: "Kontynuuj oglądanie", nextUp: "Następne"),
        "pt": TopShelfText(continueWatching: "Continuar a ver", nextUp: "A seguir"),
        "pt-BR": TopShelfText(continueWatching: "Continuar assistindo", nextUp: "A seguir"),
        "ro": TopShelfText(continueWatching: "Continuă vizionarea", nextUp: "Urmează"),
        "ru": TopShelfText(continueWatching: "Продолжить просмотр", nextUp: "Далее"),
        "sl": TopShelfText(continueWatching: "Nadaljuj z ogledom", nextUp: "Naslednje"),
        "sv": TopShelfText(continueWatching: "Fortsätt titta", nextUp: "Nästa"),
        "tr": TopShelfText(continueWatching: "İzlemeye devam et", nextUp: "Sıradaki"),
        "zh-Hans": TopShelfText(continueWatching: "继续观看", nextUp: "接下来播放"),
    ]
}
