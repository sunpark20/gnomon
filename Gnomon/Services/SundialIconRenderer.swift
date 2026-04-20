//
//  SundialIconRenderer.swift
//  Gnomon
//
//  Programmatically renders a sundial NSImage whose shadow rotates with the
//  hour of day. Used both for the Dock (NSApp.applicationIconImage) and the
//  menu bar (NSStatusItem.button.image).
//
//  The sundial is stylized — not astronomically accurate. The rotation
//  follows a 24-hour clock convention so it matches user intuition:
//    - 00:00 / 24:00: shadow points up
//    - 06:00: shadow points right
//    - 12:00 (noon): shadow points down
//    - 18:00: shadow points left
//    - minutes are interpolated, so 23:39 sits slightly past the "up-left" hour mark
//

import AppKit
import CoreGraphics

public enum SundialIconRenderer {
    public struct Style: Sendable {
        public let diameter: CGFloat
        public let faceColor: NSColor
        public let rimColor: NSColor
        public let tickColor: NSColor
        public let gnomonColor: NSColor
        public let shadowColor: NSColor

        public static let dock = Style(
            diameter: 512,
            faceColor: NSColor(red: 0.96, green: 0.94, blue: 0.88, alpha: 1),
            rimColor: NSColor(red: 0.61, green: 0.50, blue: 0.26, alpha: 1),
            tickColor: NSColor(red: 0.47, green: 0.38, blue: 0.18, alpha: 1),
            gnomonColor: NSColor(red: 0.47, green: 0.38, blue: 0.18, alpha: 1),
            shadowColor: NSColor(red: 0.30, green: 0.20, blue: 0.08, alpha: 0.85)
        )

        public static let menuBarActive = Style(
            diameter: 32,
            faceColor: NSColor.clear,
            rimColor: NSColor(red: 0.96, green: 0.60, blue: 0.10, alpha: 1),
            tickColor: NSColor(red: 0.96, green: 0.60, blue: 0.10, alpha: 1),
            gnomonColor: NSColor(red: 0.96, green: 0.60, blue: 0.10, alpha: 1),
            shadowColor: NSColor(red: 0.96, green: 0.60, blue: 0.10, alpha: 1)
        )

        public static let menuBarInactive = Style(
            diameter: 32,
            faceColor: NSColor.clear,
            rimColor: NSColor.secondaryLabelColor,
            tickColor: NSColor.tertiaryLabelColor,
            gnomonColor: NSColor.secondaryLabelColor,
            shadowColor: NSColor.secondaryLabelColor
        )
    }

    /// Converts time-of-day into shadow rotation in degrees, measured clockwise from straight up.
    /// 00:00 = 0°, 06:00 = 90° (right), 12:00 = 180° (down), 18:00 = 270° (left).
    public static func shadowAngle(hour: Int, minute: Int = 0) -> CGFloat {
        let fractional = (Double(hour) + Double(minute) / 60.0).truncatingRemainder(dividingBy: 24)
        return CGFloat(fractional * 15)
    }

    public static func image(hour: Int, minute: Int = 0, style: Style) -> NSImage {
        let size = NSSize(width: style.diameter, height: style.diameter)
        let image = NSImage(size: size, flipped: false) { rect in
            draw(in: rect, hour: hour, minute: minute, style: style)
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func draw(in rect: CGRect, hour: Int, minute: Int, style: Style) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let scale = rect.width / style.diameter
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = style.diameter * 0.42 * scale
        drawFace(ctx: ctx, center: center, radius: radius, style: style, scale: scale)
        drawTicks(ctx: ctx, center: center, radius: radius, style: style, scale: scale)
        drawShadow(
            ctx: ctx,
            params: ShadowParams(center: center, radius: radius, hour: hour, minute: minute),
            style: style,
            scale: scale
        )
        drawCenterDot(ctx: ctx, center: center, style: style, scale: scale)
    }

    private static func drawFace(
        ctx: CGContext,
        center: CGPoint,
        radius: CGFloat,
        style: Style,
        scale: CGFloat
    ) {
        let bounds = CGRect(
            x: center.x - radius, y: center.y - radius,
            width: radius * 2, height: radius * 2
        )
        ctx.saveGState()
        ctx.setFillColor(style.faceColor.cgColor)
        ctx.fillEllipse(in: bounds)
        ctx.restoreGState()

        ctx.saveGState()
        ctx.setStrokeColor(style.rimColor.cgColor)
        ctx.setLineWidth(max(1.5, style.diameter * 0.01 * scale))
        ctx.strokeEllipse(in: bounds)
        ctx.restoreGState()
    }

    private static func drawTicks(
        ctx: CGContext,
        center: CGPoint,
        radius: CGFloat,
        style: Style,
        scale: CGFloat
    ) {
        ctx.saveGState()
        ctx.setStrokeColor(style.tickColor.cgColor)
        for tick in 0 ..< 12 {
            let angle = CGFloat(tick) * 30 * .pi / 180
            let isCardinal = tick % 3 == 0
            let outer = radius
            let inner = radius * (isCardinal ? 0.78 : 0.86)
            ctx.setLineWidth(max(0.6, (isCardinal ? 1.8 : 1.0) * scale * style.diameter * 0.004))
            ctx.move(to: CGPoint(
                x: center.x + sin(angle) * inner,
                y: center.y + cos(angle) * inner
            ))
            ctx.addLine(to: CGPoint(
                x: center.x + sin(angle) * outer,
                y: center.y + cos(angle) * outer
            ))
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    private struct ShadowParams {
        let center: CGPoint
        let radius: CGFloat
        let hour: Int
        let minute: Int
    }

    private static func drawShadow(
        ctx: CGContext,
        params: ShadowParams,
        style: Style,
        scale: CGFloat
    ) {
        let angle = shadowAngle(hour: params.hour, minute: params.minute) * .pi / 180
        let shadowLength = params.radius * 0.88
        ctx.saveGState()
        ctx.setStrokeColor(style.shadowColor.cgColor)
        ctx.setLineCap(.round)
        ctx.setLineWidth(max(2, style.diameter * 0.022 * scale))
        ctx.move(to: params.center)
        // y-axis is up in the unflipped coordinate space; 0° must point up so
        // cos contributes positively (not negatively as in the prior sundial
        // convention where noon pointed down).
        ctx.addLine(to: CGPoint(
            x: params.center.x + sin(angle) * shadowLength,
            y: params.center.y + cos(angle) * shadowLength
        ))
        ctx.strokePath()
        ctx.restoreGState()
    }

    private static func drawCenterDot(ctx: CGContext, center: CGPoint, style: Style, scale: CGFloat) {
        ctx.saveGState()
        ctx.setFillColor(style.gnomonColor.cgColor)
        let dotRadius = max(2, style.diameter * 0.04 * scale)
        ctx.fillEllipse(in: CGRect(
            x: center.x - dotRadius,
            y: center.y - dotRadius,
            width: dotRadius * 2,
            height: dotRadius * 2
        ))
        ctx.restoreGState()
    }
}
