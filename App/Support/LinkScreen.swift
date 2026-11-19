import UIKit

/**
 * A web link the page opened (Donate, About's links and credits, Account's configuration page, any
 * other), as a QR code for a phone's camera and as text: a TV has no browser to open it in. Menu or
 * Done closes it. Its words are in the page's language, among those the web app has catalogs for.
 */
final class LinkScreen: UIViewController {
    /// The screen has closed, however it was.
    var closed: () -> Void = {}

    private let url: URL
    /// The page's language (`tvos-language`), which the screen's text follows.
    private let language: String
    private let done = UIButton(type: .system)

    init(url: URL, language: String) {
        self.url = url
        self.language = language
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not from a storyboard") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(white: 0, alpha: 0.85)

        let text = Self.text(for: language)
        let title = UILabel()
        title.text = text.title
        title.font = .systemFont(ofSize: 48, weight: .bold)
        title.textColor = .white

        let qr = UIImageView(image: QRCode.image(for: url.absoluteString, size: Self.codeSize))
        qr.contentMode = .scaleAspectFit
        qr.layer.magnificationFilter = .nearest
        qr.backgroundColor = .white
        qr.layer.cornerRadius = 12
        qr.clipsToBounds = true

        let address = UILabel()
        address.text = url.absoluteString
        address.font = .monospacedSystemFont(ofSize: 30, weight: .medium)
        address.textColor = .white
        address.textAlignment = .center
        address.numberOfLines = 2
        address.lineBreakMode = .byCharWrapping
        address.adjustsFontSizeToFitWidth = true
        address.minimumScaleFactor = 0.5

        let note = UILabel()
        note.text = text.note
        note.font = .systemFont(ofSize: 26)
        note.textColor = UIColor(white: 0.75, alpha: 1)
        note.numberOfLines = 0
        note.textAlignment = .center

        done.setTitle(text.done, for: .normal)
        done.addTarget(self, action: #selector(close), for: .primaryActionTriggered)

        let column = UIStackView(arrangedSubviews: [title, qr, address, note, done])
        column.axis = .vertical
        column.alignment = .center
        column.spacing = 32
        column.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(column)
        NSLayoutConstraint.activate([
            column.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            column.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            column.widthAnchor.constraint(equalToConstant: 1100),
            qr.widthAnchor.constraint(equalToConstant: Self.codeSize),
            qr.heightAnchor.constraint(equalToConstant: Self.codeSize),
            address.widthAnchor.constraint(equalTo: column.widthAnchor),
            note.widthAnchor.constraint(equalTo: column.widthAnchor),
        ])
    }

    override var preferredFocusEnvironments: [UIFocusEnvironment] { [done] }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        closed()
    }

    @objc private func close() {
        dismiss(animated: true)
    }

    private static let codeSize: CGFloat = 420

    // MARK: Text

    /// The screen's words in one language.
    struct Text {
        let title: String
        let note: String
        let done: String
    }

    /// The page's language, else one in the same language, else British English (`AppLanguage`).
    static func text(for language: String) -> Text { AppLanguage.pick(texts, for: language) }

    /// In the languages the web app has catalogs for, addressing the reader as each catalog does.
    private static let texts: [String: Text] = [
        "en-GB": Text(
            title: "Open on your phone",
            note: "Scan the code with your phone's camera to open this link there, or type the address.",
            done: "Done"
        ),
        "ar": Text(
            title: "افتحه على هاتفك",
            note: "امسح الرمز بكاميرا هاتفك لفتح هذا الرابط عليه، أو اكتب العنوان.",
            done: "تم"
        ),
        "ca": Text(
            title: "Obre-ho al telèfon",
            note: "Escaneja el codi amb la càmera del telèfon per obrir-hi aquest enllaç, o escriu l'adreça.",
            done: "Fet"
        ),
        "de": Text(
            title: "Auf dem Handy öffnen",
            note: "Scanne den Code mit der Kamera deines Handys, um den Link dort zu öffnen, oder gib die Adresse ein.",
            done: "Fertig"
        ),
        "el": Text(
            title: "Άνοιξέ το στο τηλέφωνό σου",
            note: "Σάρωσε τον κωδικό με την κάμερα του τηλεφώνου σου για να ανοίξεις εκεί τον σύνδεσμο, ή πληκτρολόγησε τη διεύθυνση.",
            done: "Τέλος"
        ),
        "es": Text(
            title: "Ábrelo en tu móvil",
            note: "Escanea el código con la cámara de tu móvil para abrir este enlace allí, o escribe la dirección.",
            done: "Listo"
        ),
        "fi": Text(
            title: "Avaa puhelimessa",
            note: "Skannaa koodi puhelimesi kameralla avataksesi linkin siellä, tai kirjoita osoite.",
            done: "Valmis"
        ),
        "fr": Text(
            title: "Ouvrir sur votre téléphone",
            note: "Scannez le code avec l'appareil photo de votre téléphone pour y ouvrir ce lien, ou saisissez l'adresse.",
            done: "OK"
        ),
        "id": Text(
            title: "Buka di ponsel Anda",
            note: "Pindai kode dengan kamera ponsel Anda untuk membuka tautan ini di sana, atau ketik alamatnya.",
            done: "Selesai"
        ),
        "it": Text(
            title: "Apri sul telefono",
            note: "Inquadra il codice con la fotocamera del tuo telefono per aprire lì questo link, oppure digita l'indirizzo.",
            done: "Fine"
        ),
        "ms": Text(
            title: "Buka pada telefon anda",
            note: "Imbas kod dengan kamera telefon anda untuk membuka pautan ini di sana, atau taip alamatnya.",
            done: "Selesai"
        ),
        "nb": Text(
            title: "Åpne på telefonen",
            note: "Skann koden med kameraet på telefonen din for å åpne lenken der, eller skriv inn adressen.",
            done: "Ferdig"
        ),
        "nl": Text(
            title: "Openen op je telefoon",
            note: "Scan de code met de camera van je telefoon om deze link daar te openen, of typ het adres.",
            done: "Gereed"
        ),
        "pl": Text(
            title: "Otwórz na telefonie",
            note: "Zeskanuj kod aparatem telefonu, aby otworzyć tam ten link, lub wpisz adres.",
            done: "Gotowe"
        ),
        "pt": Text(
            title: "Abrir no telemóvel",
            note: "Leia o código com a câmara do seu telemóvel para abrir esta ligação lá, ou escreva o endereço.",
            done: "Concluído"
        ),
        "pt-BR": Text(
            title: "Abrir no celular",
            note: "Escaneie o código com a câmera do seu celular para abrir este link nele, ou digite o endereço.",
            done: "OK"
        ),
        "ro": Text(
            title: "Deschide pe telefon",
            note: "Scanează codul cu camera telefonului tău pentru a deschide linkul acolo sau introdu adresa.",
            done: "Gata"
        ),
        "ru": Text(
            title: "Откройте на телефоне",
            note: "Отсканируйте код камерой телефона, чтобы открыть эту ссылку на нём, или введите адрес.",
            done: "Готово"
        ),
        "sl": Text(
            title: "Odprite v telefonu",
            note: "Optično preberite kodo s kamero telefona, da povezavo odprete tam, ali vnesite naslov.",
            done: "Končano"
        ),
        "sv": Text(
            title: "Öppna på telefonen",
            note: "Skanna koden med telefonens kamera för att öppna länken där, eller skriv in adressen.",
            done: "Klar"
        ),
        "tr": Text(
            title: "Telefonunuzda açın",
            note: "Bu bağlantıyı telefonunuzda açmak için kodu telefonunuzun kamerasıyla tarayın veya adresi yazın.",
            done: "Bitti"
        ),
        "zh-Hans": Text(
            title: "在手机上打开",
            note: "用手机相机扫描二维码即可在手机上打开此链接，也可以手动输入地址。",
            done: "完成"
        ),
    ]
}
