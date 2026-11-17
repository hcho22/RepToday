import AVFoundation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The user's profile photo in a circle, or - with none set - the `sun` disc with the profile icon the
/// Profile header has always shown. Decorative: the control or row around it carries the words.
struct ProfileAvatar: View {
    let image: UIImage?
    let diameter: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: diameter, height: diameter)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Theme.Colors.line, lineWidth: 1))
            } else {
                ZStack {
                    Circle().fill(Theme.Colors.sun)
                    IconView(icon: .profile, size: diameter * 0.48)
                        .foregroundStyle(Theme.Colors.onAccent)
                }
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }
}

/// The Profile header's avatar as a button: it opens the choices to take a photo, choose one from the
/// library, or remove the one set, then the square crop, and saves the result through
/// `ProfilePhotoModel`.
///
/// The library opens in the system photo picker, which needs no photo-library permission. The camera
/// is offered only when the phone has one and the user has not refused it; after a refusal the
/// choices offer the way to Settings instead. No permission prompt appears until Take Photo is chosen.
struct ProfilePhotoButton: View {
    let model: ProfilePhotoModel
    let diameter: CGFloat

    @State private var isChoosingSource = false
    @State private var camera = CameraAvailability.unavailable
    @State private var isPickingFromLibrary = false
    /// A photo chosen in the library, read and cropped once the picker's sheet has gone.
    @State private var libraryPick: NSItemProvider?
    @State private var cover: Cover?
    /// A photo the camera just took, cropped once the camera's cover has gone.
    @State private var capturedPhoto: UIImage?
    @State private var isCameraRefusedAlertPresented = false
    @State private var isUnreadablePhotoAlertPresented = false
    @Environment(\.openURL) private var openURL

    /// The one full-screen cover: the camera, or the crop.
    private enum Cover: Identifiable {
        case camera
        case crop(CropSource)

        var id: String {
            switch self {
            case .camera: return "camera"
            case .crop(let source): return source.id.uuidString
            }
        }
    }

    var body: some View {
        Button {
            camera = .current
            isChoosingSource = true
        } label: {
            ProfileAvatar(image: model.image, diameter: diameter)
                .overlay(alignment: .bottomTrailing) { badge }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Profile photo")
        .accessibilityValue(model.hasPhoto ? "Photo set" : "No photo")
        .accessibilityHint(model.hasPhoto ? "Change or remove your photo" : "Take a photo or choose one")
        .confirmationDialog("Profile photo", isPresented: $isChoosingSource, titleVisibility: .hidden) {
            switch camera {
            case .available:
                Button("Take Photo") { Task { await takePhoto() } }
            case .deniedInSettings:
                Button("Allow Camera in Settings") { openSettings() }
            case .unavailable:
                EmptyView()
            }
            Button("Choose from Library") { isPickingFromLibrary = true }
            if model.hasPhoto {
                Button("Remove Photo", role: .destructive) { model.removePhoto() }
            }
            Button("Cancel", role: .cancel) {}
        }
        // The crop opens from the sheet's `onDismiss`, as it does from the camera's cover: a cover
        // presented while the picker is still sliding away gets no safe area, which put the crop's
        // header under the status bar and its buttons over the home indicator.
        .sheet(isPresented: $isPickingFromLibrary, onDismiss: cropLibraryPick) {
            LibraryPhotoPicker { provider in
                libraryPick = provider
                isPickingFromLibrary = false
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(item: $cover, onDismiss: cropCapturedPhoto) { cover in
            switch cover {
            case .camera:
                CameraCaptureView { image in
                    capturedPhoto = image
                    self.cover = nil
                } onCancel: {
                    self.cover = nil
                }
                .ignoresSafeArea()
            case .crop(let source):
                ProfilePhotoCropView(image: source.image) { jpeg in
                    model.setPhoto(jpeg)
                    self.cover = nil
                } onCancel: {
                    self.cover = nil
                }
            }
        }
        .alert("Camera access is off", isPresented: $isCameraRefusedAlertPresented) {
            Button("Open Settings") { openSettings() }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("To take a profile photo, allow Rep Today to use the camera in Settings. You can still choose a photo from your library.")
        }
        .alert("That photo couldn't be opened", isPresented: $isUnreadablePhotoAlertPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Try another photo.")
        }
        .alert("Your photo wasn't saved", isPresented: Binding(get: { model.saveFailed }, set: { if !$0 { model.acknowledgeSaveFailure() } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("There wasn't room to save it on this phone. Try again after freeing some space.")
        }
    }

    /// The camera mark at the avatar's lower edge, saying the photo can be changed.
    private var badge: some View {
        ZStack {
            Circle().fill(Theme.Colors.surface2)
            IconView(icon: .camera, size: diameter * 0.2)
                .foregroundStyle(Theme.Colors.text1)
        }
        .frame(width: diameter * 0.36, height: diameter * 0.36)
        .overlay(Circle().strokeBorder(Theme.Colors.background, lineWidth: 3))
        .offset(x: 2, y: 2)
        .accessibilityHidden(true)
    }

    /// Asks for camera access the first time, then opens the camera.
    private func takePhoto() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cover = .camera
        case .notDetermined:
            if await AVCaptureDevice.requestAccess(for: .video) {
                cover = .camera
            } else {
                isCameraRefusedAlertPresented = true
            }
        default:
            isCameraRefusedAlertPresented = true
        }
    }

    /// After the picker's sheet has gone, the photo chosen in it goes to the crop.
    private func cropLibraryPick() {
        guard let provider = libraryPick else { return }
        libraryPick = nil
        Task { await loadFromLibrary(provider) }
    }

    private func loadFromLibrary(_ provider: NSItemProvider) async {
        let data = await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
        guard let data, let image = UIImage(data: data) else {
            isUnreadablePhotoAlertPresented = true
            return
        }
        cover = .crop(CropSource(image: ProfilePhotoProcessing.upright(image)))
    }

    /// After the camera's cover has gone, the photo it took goes to the crop.
    private func cropCapturedPhoto() {
        guard let photo = capturedPhoto else { return }
        capturedPhoto = nil
        cover = .crop(CropSource(image: ProfilePhotoProcessing.upright(photo)))
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }
}

/// A photo waiting to be cropped.
struct CropSource: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// The square crop: the photo under a round frame the size of the avatar, dragged to place and
/// pinched to zoom, then cropped, downscaled and compressed (`ProfilePhotoProcessing`). The frame
/// starts on the photo's centered square, so Use Photo straight away gives a sensible crop, and
/// VoiceOver users zoom with the adjustable action.
struct ProfilePhotoCropView: View {
    let image: UIImage
    let onChoose: (Data) -> Void
    let onCancel: () -> Void

    @State private var zoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @GestureState private var pinch: CGFloat = 1
    @GestureState private var drag: CGSize = .zero
    @State private var isSaving = false

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Text("Move and scale")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.text1)
                .padding(.top, Theme.Spacing.md)
                .accessibilityAddTraits(.isHeader)

            GeometryReader { proxy in
                let frameSide = max(1, min(proxy.size.width - 2 * Theme.Spacing.screenMargin, proxy.size.height))
                let geometry = ProfilePhotoCropGeometry(
                    imageSize: ProfilePhotoProcessing.uprightPixelSize(of: image), frameSide: frameSide
                )
                let liveZoom = geometry.clampedZoom(zoom * pinch)
                let liveOffset = geometry.clampedOffset(
                    CGSize(width: offset.width + drag.width, height: offset.height + drag.height), zoom: liveZoom
                )
                let displayed = geometry.displayedSize(zoom: liveZoom)

                ZStack {
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: displayed.width, height: displayed.height)
                        .offset(liveOffset)
                    // Everything outside the round frame is dimmed, so the user sees the avatar it makes.
                    CropScrim(frameSide: frameSide)
                        .fill(Theme.Colors.scrim, style: FillStyle(eoFill: true))
                        .allowsHitTesting(false)
                    Circle()
                        .strokeBorder(Theme.Colors.text1.opacity(0.9), lineWidth: 2)
                        .frame(width: frameSide, height: frameSide)
                        .allowsHitTesting(false)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
                .contentShape(Rectangle())
                .gesture(
                    SimultaneousGesture(
                        MagnifyGesture().updating($pinch) { value, state, _ in state = value.magnification },
                        DragGesture().updating($drag) { value, state, _ in state = value.translation }
                    )
                    .onEnded { value in
                        let newZoom = geometry.clampedZoom(zoom * (value.first?.magnification ?? 1))
                        let translation = value.second?.translation ?? .zero
                        offset = geometry.clampedOffset(
                            CGSize(width: offset.width + translation.width, height: offset.height + translation.height),
                            zoom: newZoom
                        )
                        zoom = newZoom
                    }
                )
                .accessibilityElement()
                .accessibilityLabel("Photo crop")
                .accessibilityValue("\(Int((liveZoom * 100).rounded())) percent zoom")
                .accessibilityHint("Swipe up or down to zoom. Drag to move the photo.")
                .accessibilityAdjustableAction { direction in
                    let step: CGFloat = direction == .increment ? 0.25 : -0.25
                    zoom = geometry.clampedZoom(zoom + step)
                    offset = geometry.clampedOffset(offset, zoom: zoom)
                }
                .onChange(of: frameSide) { _, _ in
                    offset = geometry.clampedOffset(offset, zoom: zoom)
                }
                .background(Color.clear.onAppear { cropGeometry = geometry })
                .onChange(of: geometry) { _, newValue in cropGeometry = newValue }
            }

            HStack(spacing: Theme.Spacing.smd) {
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(Theme.Typography.button)
                        .frame(maxWidth: .infinity, minHeight: Theme.Spacing.buttonHeight)
                }
                .secondaryButtonStyle()
                Button {
                    choose()
                } label: {
                    Text("Use Photo")
                        .font(Theme.Typography.button)
                        .frame(maxWidth: .infinity, minHeight: Theme.Spacing.buttonHeight)
                }
                .accentFilledButtonStyle()
                .disabled(isSaving)
            }
            .padding(.horizontal, Theme.Spacing.screenMargin)
            .padding(.bottom, Theme.Spacing.md)
        }
        .background(Theme.Colors.background.ignoresSafeArea())
    }

    /// The geometry the frame last laid out with, read when Use Photo is tapped.
    @State private var cropGeometry: ProfilePhotoCropGeometry?

    private func choose() {
        guard let cropGeometry else { return }
        isSaving = true
        let crop = cropGeometry.normalizedCrop(zoom: zoom, offset: offset)
        guard let jpeg = ProfilePhotoProcessing.croppedPhoto(from: image, normalizedCrop: crop) else {
            isSaving = false
            return
        }
        onChoose(jpeg)
    }
}

/// The crop screen's dimming: the whole area with the round frame cut out of its center.
private struct CropScrim: Shape {
    let frameSide: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        path.addEllipse(in: CGRect(
            x: rect.midX - frameSide / 2, y: rect.midY - frameSide / 2, width: frameSide, height: frameSide
        ))
        return path
    }
}

/// The system photo picker, for one photo. It needs no photo-library permission; `onFinish` gets the
/// chosen photo, or nil when the user cancels.
struct LibraryPhotoPicker: UIViewControllerRepresentable {
    let onFinish: (NSItemProvider?) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 1
        configuration.preferredAssetRepresentationMode = .compatible
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onFinish: (NSItemProvider?) -> Void

        init(onFinish: @escaping (NSItemProvider?) -> Void) {
            self.onFinish = onFinish
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            onFinish(results.first?.itemProvider)
        }
    }
}

/// The system camera, for one still photo. Its own editing is off: the crop is Rep Today's.
struct CameraCaptureView: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.cameraDevice = UIImagePickerController.isCameraDeviceAvailable(.front) ? .front : .rear
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onCancel: onCancel)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage) -> Void
        let onCancel: () -> Void

        init(onCapture: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onCancel = onCancel
        }

        func imagePickerController(
            _ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onCapture(image)
            } else {
                onCancel()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }
    }
}
