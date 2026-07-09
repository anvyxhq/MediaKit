//
//  Items.swift
//  StickerKit
//
//  Created by AnhPT on 03/07/2026.
//

import UIKit

/// A text sticker. Size yourself via ``fit(width:)`` or an explicit frame.
public final class TextItemView: TransformableItemView {
    public let label = UILabel()

    public init(id: String = UUID().uuidString, text: String, font: UIFont = .systemFont(ofSize: 24),
                textColor: UIColor = .label, frame: CGRect) {
        super.init(id: id, frame: frame)
        label.text = text
        label.font = font
        label.textColor = textColor
        label.textAlignment = .center
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        content = label
    }

    public var text: String? {
        get { label.text }
        set { label.text = newValue }
    }

    public override func contentKind() -> StickerContentKind? {
        .text(label.text ?? "", font: label.font, color: label.textColor)
    }
}

/// An image sticker (photos, signatures, stamps).
public final class ImageItemView: TransformableItemView {
    public let imageView = UIImageView()

    public init(id: String = UUID().uuidString, image: UIImage, frame: CGRect) {
        super.init(id: id, frame: frame)
        imageView.image = image
        imageView.contentMode = .scaleAspectFit
        content = imageView
    }

    public override func contentKind() -> StickerContentKind? {
        .image(imageView.image ?? UIImage())
    }
}
