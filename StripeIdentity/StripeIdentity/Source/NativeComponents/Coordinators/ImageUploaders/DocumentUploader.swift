//
//  DocumentUploader.swift
//  StripeIdentity
//
//  Created by Mel Ludowise on 12/8/21.
//

import Foundation
import UIKit
@_spi(STP) import StripeCore
@_spi(STP) import StripeCameraCore

protocol DocumentUploaderDelegate: AnyObject {
    func documentUploaderDidUpdateStatus(_ documentUploader: DocumentUploader)
    
    func frontUploaded()
    
    func backUploaded()
}

protocol DocumentUploaderProtocol: AnyObject {

    /// Tuple of front and back document file data
    typealias CombinedFileData = (
        front: StripeAPI.VerificationPageDataDocumentFileData?,
        back: StripeAPI.VerificationPageDataDocumentFileData?
    )

    var delegate: DocumentUploaderDelegate? { get set }

    var frontUploadStatus: DocumentUploader.UploadStatus { get }
    var backUploadStatus: DocumentUploader.UploadStatus { get }

    var frontBackUploadFuture: Future<CombinedFileData> { get }
    
    var frontUploadFuture: Future<StripeAPI.VerificationPageDataDocumentFileData>? { get }
    var backUploadFuture: Future<StripeAPI.VerificationPageDataDocumentFileData>? { get }

    var isFrontUpdated: Bool { get set }
    var isBackUpdated: Bool { get set }
    
    func uploadImages(
        for side: DocumentSide,
        originalImage: CGImage,
        documentScannerOutput: DocumentScannerOutput?,
        exifMetadata: CameraExifMetadata?,
        method: StripeAPI.VerificationPageDataDocumentFileData.FileUploadMethod
    )

    func reset()
}

final class DocumentUploader: DocumentUploaderProtocol {

    enum UploadStatus {
        case notStarted
        case inProgress
        case complete
        case error(Error)
    }

    weak var delegate: DocumentUploaderDelegate?

    let imageUploader: IdentityImageUploader
    
    /// Whether VerificaionPageData was already updated with front image
    var isFrontUpdated = false
    /// Whether VerificaionPageData was already updated with back image
    var isBackUpdated = false

    /// Future that is fulfilled when front images are uploaded to the server.
    /// Value is nil if upload has not been requested.
    var frontUploadFuture: Future<StripeAPI.VerificationPageDataDocumentFileData>? {
        didSet {
            guard oldValue !== frontUploadFuture else {
                return
            }
            frontUploadStatus = (frontUploadFuture == nil) ? .notStarted : .inProgress
            frontUploadFuture?.observe { [weak self, weak frontUploadFuture] result in
                // Only update `frontUploadStatus` if `frontUploadFuture` has not been reassigned
                guard let self = self,
                      frontUploadFuture === self.frontUploadFuture else {
                    return
                }
                switch result {
                case .success:
                    self.frontUploadStatus = .complete
                case .failure(let error):
                    self.frontUploadStatus = .error(error)
                }
            }
        }
    }

    /// Future that is fulfilled when back images are uploaded to the server.
    /// Value is nil if upload has not been requested.
    var backUploadFuture: Future<StripeAPI.VerificationPageDataDocumentFileData>? {
        didSet {
            guard oldValue !== backUploadFuture else {
                return
            }
            backUploadStatus = (backUploadFuture == nil) ? .notStarted : .inProgress
            backUploadFuture?.observe { [weak self, weak backUploadFuture] result in
                // Only update `backUploadStatus` if `backUploadFuture` has not been reassigned
                guard let self = self,
                      backUploadFuture === self.backUploadFuture else {
                    return
                }
                switch result {
                case .success:
                    self.backUploadStatus = .complete
                case .failure(let error):
                    self.backUploadStatus = .error(error)
                }
            }
        }
    }

    /// Status of whether the front images have finished uploading
    private(set) var frontUploadStatus: UploadStatus = .notStarted {
        didSet {
            delegate?.documentUploaderDidUpdateStatus(self)
            
            switch(frontUploadStatus) {
            case .complete:
                delegate?.frontUploaded()
            default: break
            }
        }
    }
    /// Status of whether the back images have finished uploading
    private(set) var backUploadStatus: UploadStatus = .notStarted {
        didSet {
            delegate?.documentUploaderDidUpdateStatus(self)
            
            switch(backUploadStatus) {
            case .complete:
                delegate?.backUploaded()
            default: break
            }
        }
    }

    /// Combined future that returns a tuple of front & back uploads
    var frontBackUploadFuture: Future<CombinedFileData> {
        // Unwrap futures by converting
        // from Future<VerificationPageDataDocumentFileData>?
        // to Future<VerificationPageDataDocumentFileData?>
        let unwrappedFrontUploadFuture: Future<StripeAPI.VerificationPageDataDocumentFileData?> = frontUploadFuture?.chained { Promise(value: $0) } ?? Promise(value: nil)
        let unwrappedBackUploadFuture: Future<StripeAPI.VerificationPageDataDocumentFileData?> = backUploadFuture?.chained { Promise(value: $0) } ?? Promise(value: nil)

        return unwrappedFrontUploadFuture.chained { frontData in
            return unwrappedBackUploadFuture.chained { Promise(value: (front: frontData, back: $0)) }
        }
    }

    init(imageUploader: IdentityImageUploader) {
        self.imageUploader = imageUploader
    }

    /**
     Uploads a high and low resolution image for a specific side of the
     document and updates either `frontUploadFuture` or `backUploadFuture`.
     - Note: If `idDetectorOutput` is non-nil, the high-res image will be
     cropped and an un-cropped image will be uploaded as the low-res image.
     If `idDetectorOutput` is nil, then only a high-res image will be
     uploaded and it will not be cropped.
     - Parameters:
       - side: The side of the image (front or back) to upload.
       - originalImage: The original image captured or uploaded by the user.
       - idDetectorOutput: The output from the IDDetector model
       - method: The method the image was obtained.
     */
    func uploadImages(
        for side: DocumentSide,
        originalImage: CGImage,
        documentScannerOutput: DocumentScannerOutput?,
        exifMetadata: CameraExifMetadata?,
        method: StripeAPI.VerificationPageDataDocumentFileData.FileUploadMethod
    ) {
       
        switch side {
        case .front:
            self.isFrontUpdated = false
        case .back:
            self.isBackUpdated = false
        }
        
        let uploadFuture = uploadImages(
            originalImage,
            documentScannerOutput: documentScannerOutput,
            exifMetadata: exifMetadata,
            method: method,
            fileNamePrefix: "\(imageUploader.apiClient.verificationSessionId)_\(side.rawValue)"
        )

        switch side {
        case .front:
            self.frontUploadFuture = uploadFuture
        case .back:
            self.backUploadFuture = uploadFuture
        }
    }

    /// Uploads both a high and low resolution image
    func uploadImages(
        _ originalImage: CGImage,
        documentScannerOutput: DocumentScannerOutput?,
        exifMetadata: CameraExifMetadata?,
        method: StripeAPI.VerificationPageDataDocumentFileData.FileUploadMethod,
        fileNamePrefix: String
    ) -> Future<StripeAPI.VerificationPageDataDocumentFileData> {

        // Only upload a low res image if the high res image will be cropped
        if let documentBounds = documentScannerOutput?.idDetectorOutput.documentBounds {
            return imageUploader.uploadLowAndHighResImages(
                originalImage,
                highResRegionOfInterest: documentBounds,
                cropPaddingComputationMethod: .maxImageWidthOrHeight,
                lowResFileName: "\(fileNamePrefix)_full_frame",
                highResFileName: fileNamePrefix
            ).chained { (lowResFile, highResFile) in
                return Promise(value: StripeAPI.VerificationPageDataDocumentFileData(
                    documentScannerOutput: documentScannerOutput,
                    highResImage: highResFile.id,
                    lowResImage: lowResFile.id,
                    exifMetadata: exifMetadata,
                    uploadMethod: method
                ))
            }
        } else {
            return imageUploader.uploadHighResImage(
                originalImage,
                regionOfInterest: nil,
                cropPaddingComputationMethod: .maxImageWidthOrHeight,
                fileName: fileNamePrefix
            ).chained { highResFile in
                return Promise(value: StripeAPI.VerificationPageDataDocumentFileData(
                    documentScannerOutput: documentScannerOutput,
                    highResImage: highResFile.id,
                    lowResImage: nil,
                    exifMetadata: exifMetadata,
                    uploadMethod: method
                ))
            }
        }
    }

    /// Resets the status of the uploader
    func reset() {
        frontUploadFuture = nil
        backUploadFuture = nil
        isFrontUpdated = false
        isBackUpdated = false
    }
}
