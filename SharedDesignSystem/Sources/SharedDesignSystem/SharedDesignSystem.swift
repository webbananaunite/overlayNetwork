import SwiftUI

public struct TYButtonStyle: ButtonStyle {
    public init() {}
    
    public func makeBody(configuration: Self.Configuration) -> some View {
        configuration.label
        .padding(.all, 8.0)
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(Color.red, lineWidth: 1.0)
            .frame(width: 200, height: 50, alignment: .center)
        )
        .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
    }
}

public struct TYTextFieldStyle: TextFieldStyle {
    public init() {}
    
    public func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
        .padding(.horizontal, 8.0)
        .padding(.vertical, 16.0)
        .background(RoundedRectangle(cornerRadius: 10)
        .strokeBorder(Color.red, lineWidth: 1.0))
    }
}
