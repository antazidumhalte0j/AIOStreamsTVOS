import UIKit

/**
 * tvOS's full-screen keyboard for a password or a PIN, from a text field of its own, with no alert
 * around it: the search keyboard (`SearchKeyboard`) shows what's typed, and only a secure text
 * field's keyboard hides it, as dots. Presented over the page, clear, so the page keeps its look
 * behind the keyboard and the remote goes to the keyboard while it shows. Each change goes into the
 * page's field as it comes, and once more as the keyboard closes; Done on the keyboard sends the
 * field's form, Menu closes it without.
 */
final class FieldKeyboard: UIViewController, UITextFieldDelegate {
    private let field = UITextField()
    private let onChange: (String) -> Void
    private let onClose: (_ submit: Bool) -> Void
    private var sent: String
    private var submitted = false
    private var closed = false

    init(
        text: String,
        prompt: String,
        keyboardType: UIKeyboardType,
        secure: Bool,
        onChange: @escaping (String) -> Void,
        onClose: @escaping (_ submit: Bool) -> Void
    ) {
        sent = text
        self.onChange = onChange
        self.onClose = onClose
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
        field.text = text
        field.placeholder = prompt
        field.isSecureTextEntry = secure
        field.keyboardType = keyboardType
        field.returnKeyType = .done
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.delegate = self
        field.addTarget(self, action: #selector(changed), for: .editingChanged)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not from a storyboard") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        // In the view, so it can take the keyboard, but out of sight: the keyboard shows the text.
        field.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        field.alpha = 0.02
        view.addSubview(field)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Straight to the keyboard.
        if !field.isFirstResponder { field.becomeFirstResponder() }
    }

    override var preferredFocusEnvironments: [UIFocusEnvironment] { [field] }

    @objc private func changed() { send() }

    /// What's typed, into the page's field, once for each change.
    private func send() {
        let now = field.text ?? ""
        guard now != sent else { return }
        sent = now
        onChange(now)
    }

    // MARK: UITextFieldDelegate

    /// The keyboard's Done.
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        submitted = true
        textField.resignFirstResponder()
        return false
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        send()
        dismiss(animated: true)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard !closed else { return }
        closed = true
        send()
        onClose(submitted)
    }
}
