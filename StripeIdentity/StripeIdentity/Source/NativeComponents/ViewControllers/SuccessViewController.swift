//
//  SuccessViewController.swift
//  StripeIdentity
//
//  Created by Mel Ludowise on 11/16/21.
//

import UIKit
@_spi(STP) import StripeCore
@_spi(STP) import StripeUICore

final class SuccessViewController: UIViewController {

    private let flowView = IdentityFlowView()

    // TODO(mludowise|IDPROD-2759): Use a view that matches design instead of a label
    let bodyLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 0
        return label
    }()

    init(successContent: VerificationPageStaticContentTextPage) {
        super.init(nibName: nil, bundle: nil)

        bodyLabel.text = successContent.body

        self.title = successContent.title
        // TODO(jaimepark| IDPROD-2759): Update header view to match design. It is plain for now but should be banner type.
        flowView.configure(with: .init(
            headerViewModel: .init(
                backgroundColor: CompatibleColor.systemBackground,
                headerType: .plain,
                titleText: successContent.title
            ),
            contentView:  bodyLabel,
            buttonText: successContent.buttonText,
            didTapButton: { [weak self] in
                self?.didTapButton()
            }
        ))
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Set flowView as this view controller's view
        flowView.frame = self.view.frame
        self.view = flowView
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private extension SuccessViewController {
    func didTapButton() {
        dismiss(animated: true, completion: nil)
    }
}
