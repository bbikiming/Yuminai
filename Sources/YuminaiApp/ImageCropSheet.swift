import SwiftUI
import AppKit
import CoreGraphics
import YuminaiUI

/// **ADR-108-B** — 이미지 크롭/리사이징 sheet (개선판).
///
/// 좌우 분할 레이아웃:
/// - 좌측(360×360): 큰 미리보기 + 드래그/핀치 gesture (검은 배경 + 1:1 흰 테두리 mask)
/// - 우측(280): 컨트롤 패널 (슬라이더 + 빠른 옵션 + 결과 thumbnail)
/// - 슬라이더는 보조 컨트롤 — 드래그/줌 gesture는 유지 (큰 영역에서 부드러움)
/// - 레이아웃 shift 방지: 미리보기 frame 고정 (360×360), 컨트롤 frame 고정 (280)
///
/// 사용법:
/// ```swift
/// ImageCropSheet(originalImage: nsImage) { path in
///     profileImagePath = path
/// }
/// ```
struct ImageCropSheet: View {

    // MARK: - 타입

    enum OutputSize: String, CaseIterable, Identifiable {
        case small  = "작게"
        case medium = "보통"
        case large  = "크게"

        var id: String { rawValue }

        var pixels: CGFloat {
            switch self {
            case .small:  return 128
            case .medium: return 256
            case .large:  return 512
            }
        }

        var detail: String {
            switch self {
            case .small:  return "128px"
            case .medium: return "256px"
            case .large:  return "512px"
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
    @State private var outputSize: OutputSize = .medium
    @State private var isSquare: Bool = true
    @State private var isSaving: Bool = false

    // 드래그 누적을 위한 임시값
    @State private var dragStartOffset: CGSize = .zero

    // 미리보기 + 컨트롤 고정 크기
    private let previewSize: CGFloat = 360.0
    private let controlWidth: CGFloat = 280.0

    // MARK: - body

    var body: some View {
        YuminaiSheet(width: 800, height: 560) {
            HStack(alignment: .top, spacing: 0) {
                // 좌측: 큰 미리보기
                previewColumn
                    .frame(width: previewSize + Theme.Spacing.xl * 2)

                Divider()

                // 우측: 컨트롤 패널
                controlColumn
                    .frame(width: controlWidth + Theme.Spacing.xl * 2)
            }
        } footer: {
            footerRow
        }
        .overlay(alignment: .topTrailing) {
            SheetCloseButton(action: onCancel)
        }
    }

    // MARK: - 좌측: 미리보기 컬럼

    private var previewColumn: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            // 섹션 헤더
            sectionHeader("미리보기", icon: "crop", color: Theme.Color.accent)

            // 크롭 프리뷰 영역 (고정 크기)
            ZStack {
                // 검은 배경
                Color.black
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
                                imageScale = max(0.5, min(3.0, imageScale * value))
                            }
                    )
                    .frame(width: previewSize, height: previewSize)
                    .clipped()

                // 크롭 마스크 오버레이 (흰 테두리 + 반투명 검은 테두리)
                cropMaskOverlay
            }
            .frame(width: previewSize, height: previewSize)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .stroke(Theme.Color.borderSubtle, lineWidth: 0.5)
            )

            // 드래그/핀치 안내
            Text("드래그로 위치, 핀치로 크기 조정")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
                .frame(maxWidth: previewSize, alignment: .center)
        }
        .padding(Theme.Spacing.xl)
    }

    /// 크롭 비율에 따른 마스크 오버레이.
    private var cropMaskOverlay: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let cropW: CGFloat = isSquare ? w : w
            let cropH: CGFloat = isSquare ? h : h
            let cropRect = CGRect(
                x: (w - cropW) / 2,
                y: (h - cropH) / 2,
                width: cropW,
                height: cropH
            )

            Canvas { context, size in
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black.opacity(0.50)))
                context.blendMode = .destinationOut
                context.fill(Path(cropRect), with: .color(.white))
            }
            .compositingGroup()
            .allowsHitTesting(false)

            // 흰 테두리 (크롭 경계)
            RoundedRectangle(cornerRadius: 2)
                .stroke(Color.white.opacity(0.85), lineWidth: 1.5)
                .frame(width: cropW, height: cropH)
                .position(x: cropRect.midX, y: cropRect.midY)
        }
    }

    // MARK: - 우측: 컨트롤 패널

    private var controlColumn: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            sectionHeader("크롭 설정", icon: "slider.horizontal.3", color: .purple)

            // 확대/축소 슬라이더
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack {
                    Text("확대/축소")
                        .font(Theme.Typography.small.weight(.medium))
                        .foregroundStyle(Theme.Color.text)
                    Spacer()
                    Text(String(format: "%.1f×", imageScale))
                        .font(Theme.Typography.micro.monospacedDigit())
                        .foregroundStyle(Theme.Color.textSecondary)
                        .frame(width: 36, alignment: .trailing)
                }
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "minus.magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Color.textTertiary)
                    Slider(value: $imageScale, in: 0.5...3.0, step: 0.05)
                    Image(systemName: "plus.magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Color.textTertiary)
                }
            }

            Divider()

            // 출력 크기
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("출력 크기")
                    .font(Theme.Typography.small.weight(.medium))
                    .foregroundStyle(Theme.Color.text)
                Picker("출력 크기", selection: $outputSize) {
                    ForEach(OutputSize.allCases) { size in
                        Text("\(size.rawValue) (\(size.detail))").tag(size)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text("저장 시 \(Int(outputSize.pixels))×\(Int(outputSize.pixels))px로 출력됩니다.")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
            }

            Divider()

            // 빠른 버튼들
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("빠른 조작")
                    .font(Theme.Typography.small.weight(.medium))
                    .foregroundStyle(Theme.Color.text)

                // 위치 초기화
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        imageOffset = .zero
                        dragStartOffset = .zero
                        imageScale = 1.0
                    }
                } label: {
                    Label("위치/크기 초기화", systemImage: "arrow.counterclockwise")
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.Color.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                        .padding(.horizontal, Theme.Spacing.sm)
                        .background(Theme.Color.surfaceHi)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                }
                .buttonStyle(.plain)

                // 정중앙
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        imageOffset = .zero
                        dragStartOffset = .zero
                    }
                } label: {
                    Label("이미지 정중앙", systemImage: "dot.circle")
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.Color.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                        .padding(.horizontal, Theme.Spacing.sm)
                        .background(Theme.Color.surfaceHi)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                }
                .buttonStyle(.plain)
            }

            Divider()

            // 결과 미리보기 (작은 thumbnail)
            resultThumbnail

            Spacer()
        }
        .padding(Theme.Spacing.xl)
    }

    /// 결과 출력 미리보기 thumbnail (우측 하단).
    private var resultThumbnail: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("결과 미리보기")
                .font(Theme.Typography.small.weight(.medium))
                .foregroundStyle(Theme.Color.text)

            HStack(spacing: Theme.Spacing.md) {
                // 원형 썸네일 (실제 프로필 이미지 표시 방식)
                ZStack {
                    Color.black
                    Image(nsImage: originalImage)
                        .resizable()
                        .interpolation(.medium)
                        .scaledToFit()
                        .scaleEffect(imageScale)
                        .offset(CGSize(
                            width: imageOffset.width / (previewSize / 56),
                            height: imageOffset.height / (previewSize / 56)
                        ))
                        .frame(width: 56, height: 56)
                        .clipped()
                }
                .frame(width: 56, height: 56)
                .clipShape(Circle())
                .overlay(Circle().stroke(Theme.Color.borderSubtle, lineWidth: 0.5))

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(Int(outputSize.pixels))×\(Int(outputSize.pixels))px")
                        .font(Theme.Typography.micro.monospacedDigit())
                        .foregroundStyle(Theme.Color.textSecondary)
                    Text("원형으로 표시됩니다")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textTertiary)
                }
            }
        }
    }

    // MARK: - 공통 헬퍼

    private func sectionHeader(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.Color.text)
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

        // 이미지 픽셀 좌표계로 변환
        let scaleX = srcW / (displayW * imageScale)
        let scaleY = srcH / (displayH * imageScale)

        let centerX = srcW / 2.0 - imageOffset.width * scaleX
        let centerY = srcH / 2.0 - imageOffset.height * scaleY

        let cropW = previewSize * scaleX
        let cropH = previewSize * scaleY

        let cropRect = CGRect(
            x: max(0, centerX - cropW / 2),
            y: max(0, centerY - cropH / 2),
            width: min(cropW, srcW),
            height: min(cropH, srcH)
        )

        guard let cropped = cgImage.cropping(to: cropRect) else { return nil }

        let outPx = outputSize.pixels
        let outSize = CGSize(width: outPx, height: outPx)

        guard let ctx = CGContext(
            data: nil,
            width: Int(outPx),
            height: Int(outPx),
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
