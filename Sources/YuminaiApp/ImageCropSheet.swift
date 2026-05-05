import SwiftUI
import AppKit
import CoreGraphics
import YuminaiUI

/// **ADR-107** — 이미지 크롭/리사이징 sheet.
///
/// NSOpenPanel로 선택한 이미지를 드래그 + 확대/축소로 크롭 영역을 조정하고
/// Core Graphics로 출력 이미지를 생성한다.
///
/// 사용법:
/// ```swift
/// ImageCropSheet(originalImage: nsImage) { path in
///     // path: ~/Library/Application Support/Yuminai/profile-image-<UUID>.png
///     profileImagePath = path
/// }
/// ```
struct ImageCropSheet: View {

    // MARK: - 타입

    enum AspectRatio: String, CaseIterable, Identifiable {
        case square   = "1:1"
        case fourThree = "4:3"
        case sixteenNine = "16:9"

        var id: String { rawValue }

        var ratio: CGFloat {
            switch self {
            case .square:      return 1.0
            case .fourThree:   return 4.0 / 3.0
            case .sixteenNine: return 16.0 / 9.0
            }
        }
    }

    enum OutputSize: String, CaseIterable, Identifiable {
        case small  = "small (128px)"
        case medium = "medium (256px)"
        case large  = "large (512px)"

        var id: String { rawValue }

        var pixels: CGFloat {
            switch self {
            case .small:  return 128
            case .medium: return 256
            case .large:  return 512
            }
        }
    }

    // MARK: - 입력

    let originalImage: NSImage
    let onSave: (String) -> Void
    let onCancel: () -> Void

    // MARK: - 상태

    @State private var imageOffset: CGSize = .zero
    @State private var imageScale: CGFloat = 1.0
    @State private var aspectRatio: AspectRatio = .square
    @State private var outputSize: OutputSize = .medium
    @State private var isSaving: Bool = false

    // 드래그 누적을 위한 임시값
    @State private var dragStartOffset: CGSize = .zero

    // 프리뷰 영역 크기 (GeometryReader로 측정)
    private let previewSize: CGFloat = 320.0

    // MARK: - body

    var body: some View {
        YuminaiSheet(width: 520, height: 640) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                sheetHeader
                cropPreviewCard
                controlsCard
            }
            .padding(Theme.Spacing.lg)
        } footer: {
            footerRow
        }
    }

    // MARK: - 헤더

    private var sheetHeader: some View {
        HeaderHero(
            icon: "crop",
            iconTint: Theme.Color.accent,
            title: "이미지 크롭",
            subtitle: "드래그로 위치를, 슬라이더로 크기를 조정하세요."
        )
    }

    // MARK: - 크롭 프리뷰

    private var cropPreviewCard: some View {
        CardSection(style: .elevated) {
            VStack(spacing: Theme.Spacing.md) {
                SectionHeaderRow(
                    icon: "crop",
                    iconColor: Theme.Color.accent,
                    title: "프리뷰"
                )
                ZStack {
                    // 검은 배경
                    Rectangle()
                        .fill(Color.black)
                        .frame(width: previewSize, height: previewSize)

                    // 원본 이미지 (드래그 + 핀치)
                    Image(nsImage: originalImage)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .scaleEffect(imageScale)
                        .offset(imageOffset)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    imageOffset = CGSize(
                                        width: dragStartOffset.width + value.translation.width,
                                        height: dragStartOffset.height + value.translation.height
                                    )
                                }
                                .onEnded { _ in
                                    dragStartOffset = imageOffset
                                }
                        )
                        .simultaneousGesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    imageScale = max(0.5, min(3.0, value))
                                }
                        )
                        .frame(width: previewSize, height: previewSize)
                        .clipped()

                    // 크롭 마스크 오버레이 (반투명 검은 테두리)
                    cropMaskOverlay
                }
                .frame(width: previewSize, height: previewSize)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md)
                        .stroke(Theme.Color.borderSubtle, lineWidth: 0.5)
                )
                .frame(maxWidth: .infinity)

                // 줌 슬라이더
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "minus.magnifyingglass")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.Color.textTertiary)
                    Slider(value: $imageScale, in: 0.5...3.0, step: 0.05)
                    Image(systemName: "plus.magnifyingglass")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.Color.textTertiary)
                    Text(String(format: "%.1fx", imageScale))
                        .font(Theme.Typography.micro.monospacedDigit())
                        .foregroundStyle(Theme.Color.textSecondary)
                        .frame(width: 36, alignment: .trailing)
                }

                // 리셋 버튼
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        imageOffset = .zero
                        dragStartOffset = .zero
                        imageScale = 1.0
                    }
                } label: {
                    Label("위치/크기 초기화", systemImage: "arrow.counterclockwise")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textSecondary)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    /// 크롭 비율에 따른 마스크 오버레이 (반투명 테두리).
    private var cropMaskOverlay: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let ratio = aspectRatio.ratio
            let cropW: CGFloat = ratio >= 1.0 ? w : w * ratio
            let cropH: CGFloat = ratio >= 1.0 ? h / ratio : h
            let cropRect = CGRect(
                x: (w - cropW) / 2,
                y: (h - cropH) / 2,
                width: cropW,
                height: cropH
            )

            Canvas { context, size in
                // 전체 영역 어둡게
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black.opacity(0.55)))
                // 크롭 영역 투명하게 (구멍 뚫기)
                context.blendMode = .destinationOut
                context.fill(Path(cropRect), with: .color(.white))
            }
            .compositingGroup()
            .allowsHitTesting(false)

            // 크롭 경계선
            RoundedRectangle(cornerRadius: 2)
                .stroke(Color.white.opacity(0.8), lineWidth: 1.5)
                .frame(width: cropW, height: cropH)
                .position(x: cropRect.midX, y: cropRect.midY)
        }
    }

    // MARK: - 컨트롤

    private var controlsCard: some View {
        CardSection(style: .subtle) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                SectionHeaderRow(
                    icon: "slider.horizontal.3",
                    iconColor: .purple,
                    title: "크롭 설정"
                )

                // 비율 Picker
                VStack(alignment: .leading, spacing: 4) {
                    Text("비율")
                        .font(Theme.Typography.small.weight(.medium))
                        .foregroundStyle(Theme.Color.text)
                    Picker("비율", selection: $aspectRatio) {
                        ForEach(AspectRatio.allCases) { ratio in
                            Text(ratio.rawValue).tag(ratio)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                // 출력 크기 Picker
                VStack(alignment: .leading, spacing: 4) {
                    Text("출력 크기")
                        .font(Theme.Typography.small.weight(.medium))
                        .foregroundStyle(Theme.Color.text)
                    Picker("출력 크기", selection: $outputSize) {
                        ForEach(OutputSize.allCases) { size in
                            Text(size.rawValue).tag(size)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Text("저장 시 \(Int(outputSize.pixels))×\(Int(outputSize.pixels * (1.0 / aspectRatio.ratio)))px로 출력됩니다.")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textTertiary)
                }
            }
        }
    }

    // MARK: - 푸터

    private var footerRow: some View {
        HStack {
            Spacer()
            FlatButton("취소", variant: .secondary) {
                onCancel()
            }
            .keyboardShortcut(.escape, modifiers: [])

            FlatButton(isSaving ? "저장 중…" : "저장", variant: .primary) {
                Task { await performSave() }
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(isSaving)
        }
    }

    // MARK: - 크롭 + 저장 로직

    private func performSave() async {
        isSaving = true
        defer { isSaving = false }

        guard let path = cropAndSave() else { return }
        onSave(path)
    }

    /// Core Graphics로 크롭 후 파일 저장. 경로 반환.
    private func cropAndSave() -> String? {
        guard let cgImage = originalImage.cgImage(
            forProposedRect: nil, context: nil, hints: nil
        ) else { return nil }

        let srcW = CGFloat(cgImage.width)
        let srcH = CGFloat(cgImage.height)

        // 프리뷰 영역 내 이미지 실제 표시 비율 계산 (scaledToFit 기준)
        let naturalRatio = srcW / srcH
        let displayW: CGFloat
        let displayH: CGFloat
        if naturalRatio >= 1.0 {
            displayW = previewSize
            displayH = previewSize / naturalRatio
        } else {
            displayH = previewSize
            displayW = previewSize * naturalRatio
        }

        // 크롭 창 크기 (비율에 따라)
        let ratio = aspectRatio.ratio
        let cropWindowW: CGFloat = ratio >= 1.0 ? previewSize : previewSize * ratio
        let cropWindowH: CGFloat = ratio >= 1.0 ? previewSize / ratio : previewSize

        // 이미지 픽셀 좌표계로 변환
        let scaleX = srcW / (displayW * imageScale)
        let scaleY = srcH / (displayH * imageScale)

        let centerX = srcW / 2.0 - imageOffset.width * scaleX
        let centerY = srcH / 2.0 - imageOffset.height * scaleY

        let cropW = cropWindowW * scaleX
        let cropH = cropWindowH * scaleY

        let cropRect = CGRect(
            x: max(0, centerX - cropW / 2),
            y: max(0, centerY - cropH / 2),
            width: min(cropW, srcW),
            height: min(cropH, srcH)
        )

        guard let cropped = cgImage.cropping(to: cropRect) else { return nil }

        // 출력 크기로 리사이즈
        let outPx = outputSize.pixels
        let outH = outPx / ratio
        let outSize = CGSize(width: outPx, height: outH)

        guard let ctx = CGContext(
            data: nil,
            width: Int(outPx),
            height: Int(outH),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.interpolationQuality = .high
        ctx.draw(cropped, in: CGRect(origin: .zero, size: outSize))

        guard let finalCG = ctx.makeImage() else { return nil }
        let finalImage = NSImage(cgImage: finalCG, size: outSize)

        return saveImage(finalImage)
    }

    /// NSImage를 ~/Library/Application Support/Yuminai/ 에 PNG로 저장.
    private func saveImage(_ image: NSImage) -> String? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .png, properties: [:])
        else { return nil }

        let fm = FileManager.default
        guard let supportDir = fm.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first?.appendingPathComponent("Yuminai", isDirectory: true) else { return nil }

        do {
            try fm.createDirectory(at: supportDir, withIntermediateDirectories: true)
            let url = supportDir.appendingPathComponent("profile-image-\(UUID().uuidString).png")
            try data.write(to: url)
            return url.path
        } catch {
            return nil
        }
    }
}
