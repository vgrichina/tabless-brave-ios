/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit
import Shared
import BraveShared
import Storage
import Deferred
import Data
import SnapKit

private let log = Logger.browserLogger

protocol FavoritesDelegate: AnyObject {
    func didSelect(input: String)
    func didTapDuckDuckGoCallout()
    func didTapShowMoreFavorites()
}

class FavoritesViewController: UIViewController, Themeable {
    private struct UI {
        static let statsHeight: CGFloat = 110.0
        static let statsBottomMargin: CGFloat = 5
        static let searchEngineCalloutPadding: CGFloat = 120.0
    }
    
    weak var delegate: FavoritesDelegate?
    
    // MARK: - Favorites collection view properties
    private (set) internal lazy var collection: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 6
        
        let view = UICollectionView(frame: self.view.frame, collectionViewLayout: layout).then {
            $0.backgroundColor = .clear
            $0.delegate = self
        
            let cellIdentifier = FavoriteCell.identifier
            $0.register(FavoriteCell.self, forCellWithReuseIdentifier: cellIdentifier)
            $0.keyboardDismissMode = .onDrag
            $0.alwaysBounceVertical = true
            $0.accessibilityIdentifier = "Top Sites View"
            // Entire site panel, including the stats view insets
            $0.contentInset = UIEdgeInsets(top: UI.statsHeight, left: 0, bottom: 0, right: 0)
        }
        return view
    }()
    private let dataSource: FavoritesDataSource

    private let braveShieldStatsView = BraveShieldStatsView(frame: CGRect.zero).then {
        $0.autoresizingMask = [.flexibleWidth]
    }
    
    private lazy var favoritesOverflowButton = RoundInterfaceView().then {
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .light))
        let button = UIButton(type: .system).then {
            $0.setTitle(Strings.newTabPageShowMoreFavorites, for: .normal)
            $0.appearanceTextColor = .white
            $0.titleLabel?.font = UIFont.systemFont(ofSize: 12.0, weight: .medium)
            $0.addTarget(self, action: #selector(showFavorites), for: .touchUpInside)
        }
        
        $0.clipsToBounds = true
        
        $0.addSubview(blur)
        $0.addSubview(button)
        
        blur.snp.makeConstraints { $0.edges.equalToSuperview() }
        button.snp.makeConstraints { $0.edges.equalToSuperview() }
    }

    private let ddgLogo = UIImageView(image: #imageLiteral(resourceName: "duckduckgo"))
    
    private let ddgLabel = UILabel().then {
        $0.numberOfLines = 0
        $0.textColor = BraveUX.greyD
        $0.font = UIFont.systemFont(ofSize: 14, weight: UIFont.Weight.regular)
        $0.text = Strings.DDGPromotion
    }
    
    private lazy var ddgButton = RoundInterfaceView().then {
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
        let actualButton = UIButton(type: .system).then {
            $0.addTarget(self, action: #selector(showDDGCallout), for: .touchUpInside)
        }
        $0.clipsToBounds = true
        
        $0.addSubview(blur)
        $0.addSubview(actualButton)
        
        blur.snp.makeConstraints { $0.edges.equalToSuperview() }
        actualButton.snp.makeConstraints { $0.edges.equalToSuperview() }
    }
    
    @objc private func showDDGCallout() {
        delegate?.didTapDuckDuckGoCallout()
    }
    
    @objc private func showFavorites() {
        delegate?.didTapShowMoreFavorites()
    }
    
    // MARK: - Init/lifecycle
    
    private let profile: Profile
    
    /// Whether the view was called from tapping on address bar or not.
    private let fromOverlay: Bool

    init(profile: Profile, dataSource: FavoritesDataSource = FavoritesDataSource(), fromOverlay: Bool) {
        self.profile = profile
        self.dataSource = dataSource
        self.fromOverlay = fromOverlay
        
        super.init(nibName: nil, bundle: nil)
        NotificationCenter.default.do {
            $0.addObserver(self, selector: #selector(existingUserTopSitesConversion), 
                           name: .topSitesConversion, object: nil)
            $0.addObserver(self, selector: #selector(privateBrowsingModeChanged), 
                           name: .privacyModeChanged, object: nil)
        }
    }
    
    @objc func existingUserTopSitesConversion() {
        dataSource.refetch()
        collection.reloadData()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        NotificationCenter.default.do {
            $0.removeObserver(self, name: .topSitesConversion, object: nil)
            $0.removeObserver(self, name: .privacyModeChanged, object: nil)
        }
        
        if Preferences.NewTabPage.atleastOneNTPNotificationWasShowed.value {
            // Navigating away from NTP counts the current notification as showed.
            Preferences.NewTabPage.brandedImageShowed.value = true
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.clipsToBounds = true
        
        // Setup gradient regardless of background image, can internalize to setup background image if only wanted for images.
        view.layer.addSublayer(gradientOverlay())
        
        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongGesture(gesture:)))
        collection.addGestureRecognizer(longPressGesture)
        
        view.addSubview(collection)
        collection.dataSource = dataSource
        dataSource.collectionView = collection
        
        dataSource.favoriteDeletedHandler = { [weak self] in
            self?.favoritesOverflowButton.isHidden = self?.dataSource.hasOverflow == false
        }
        
        collection.bounces = false
        
        // Could setup as section header but would need to use flow layout,
        // Auto-layout subview within collection doesn't work properly,
        // Quick-and-dirty layout here.
        var statsViewFrame: CGRect = braveShieldStatsView.frame
        statsViewFrame.origin.x = 20
        // Offset the stats view from the inset set above
        statsViewFrame.origin.y = -(UI.statsHeight + UI.statsBottomMargin)
        statsViewFrame.size.width = collection.frame.width - statsViewFrame.minX * 2
        statsViewFrame.size.height = UI.statsHeight
        braveShieldStatsView.frame = statsViewFrame
        
        collection.addSubview(braveShieldStatsView)
        collection.addSubview(favoritesOverflowButton)
        collection.addSubview(ddgButton)

        ddgButton.addSubview(ddgLogo)
        ddgButton.addSubview(ddgLabel)
        
        makeConstraints()

        // Doens't this get called twice?
        collectionContentSizeObservation = collection.observe(\.contentSize, options: [.new, .initial]) { [weak self] _, _ in
            self?.updateDuckDuckGoButtonLayout()
        }
        updateDuckDuckGoVisibility()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Need to reload data after modals are closed for potential orientation change
        // e.g. if in landscape, open portrait modal, close, the layout attempt to access an invalid indexpath
        collection.reloadData()
    }
    
    private var collectionContentSizeObservation: NSKeyValueObservation?
    
    override func viewWillLayoutSubviews() {
        updateConstraints()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        // This makes collection view layout to recalculate its cell size.
        collection.collectionViewLayout.invalidateLayout()
        favoritesOverflowButton.isHidden = !dataSource.hasOverflow
        collection.reloadSections(IndexSet(arrayLiteral: 0))
    }
    
    private func updateDuckDuckGoButtonLayout() {
        let size = ddgButton.systemLayoutSizeFitting(UIView.layoutFittingExpandedSize)
        ddgButton.frame = CGRect(
            x: ceil((collection.bounds.width - size.width) / 2.0),
            y: collection.contentSize.height + UI.searchEngineCalloutPadding,
            width: size.width,
            height: size.height
        )
    }
    
    /// Handles long press gesture for UICollectionView cells reorder.
    @objc func handleLongGesture(gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            guard let selectedIndexPath = collection.indexPathForItem(at: gesture.location(in: collection)) else {
                break
            }
            
            dataSource.isEditing = true
            collection.beginInteractiveMovementForItem(at: selectedIndexPath)
        case .changed:
            collection.updateInteractiveMovementTargetPosition(gesture.location(in: gesture.view!))
        case .ended:
            collection.endInteractiveMovement()
        default:
            collection.cancelInteractiveMovement()
        }
    }
    
    // MARK: - Constraints setup
    fileprivate func makeConstraints() {
        ddgLogo.snp.makeConstraints { make in
            make.top.left.bottom.equalTo(0)
            make.size.equalTo(38)
        }
        
        ddgLabel.snp.makeConstraints { make in
            make.top.bottom.equalTo(0)
            make.right.equalToSuperview().offset(-5)
            make.left.equalTo(self.ddgLogo.snp.right).offset(5)
            make.width.equalTo(180)
            make.centerY.equalTo(self.ddgLogo)
        }
        
        favoritesOverflowButton.snp.makeConstraints {
            $0.centerX.equalToSuperview()
            $0.bottom.equalTo(ddgButton.snp.top).offset(-90)
            $0.height.equalTo(24)
            $0.width.equalTo(84)
        }
    }
    
    // MARK: - Private browsing mode
    @objc func privateBrowsingModeChanged() {
        updateDuckDuckGoVisibility()
    }
    
    var themeableChildren: [Themeable?]? {
        return [braveShieldStatsView]
    }
    
    func applyTheme(_ theme: Theme) {
        styleChildren(theme: theme)
       
        view.backgroundColor = theme.colors.home
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        updateConstraints()
        collection.collectionViewLayout.invalidateLayout()
    }
    
    private func updateConstraints() {
        let isIphone = UIDevice.isPhone
        let isLandscape = view.frame.width > view.frame.height
        
        var right: ConstraintRelatableTarget = self.view.safeAreaLayoutGuide
        var left: ConstraintRelatableTarget = self.view.safeAreaLayoutGuide
        if isLandscape {
            if isIphone {
                left = self.view.snp.centerX
            } else {
                right = self.view.snp.centerX
            }
        }
        
        collection.snp.remakeConstraints { make in
            make.right.equalTo(right)
            make.left.equalTo(left)
            make.top.bottom.equalTo(self.view)
        }
    }
    
    fileprivate func gradientOverlay() -> CAGradientLayer {
        
        // Fades from half-black to transparent
        let colorTop = UIColor(white: 0.0, alpha: 0.5).cgColor
        let colorMid = UIColor(white: 0.0, alpha: 0.0).cgColor
        let colorBottom = UIColor(white: 0.0, alpha: 0.3).cgColor
        
        let gl = CAGradientLayer()
        gl.colors = [colorTop, colorMid, colorBottom]
        
        // Gradient cover percentage
        gl.locations = [0.0, 0.5, 0.8]
        
        // Making a squrare to handle rotation events
        let maxSide = max(view.bounds.height, view.bounds.width)
        gl.frame = CGRect(size: CGSize(width: maxSide, height: maxSide))
        
        return gl
    }
    
    // MARK: DuckDuckGo
    
    func shouldShowDuckDuckGoCallout() -> Bool {
        let isSearchEngineSet = profile.searchEngines.defaultEngine(forType: .privateMode).shortName == OpenSearchEngine.EngineNames.duckDuckGo
        let isPrivateBrowsing = PrivateBrowsingManager.shared.isPrivateBrowsing
        let shouldShowPromo = SearchEngines.shouldShowDuckDuckGoPromo
        return isPrivateBrowsing && !isSearchEngineSet && shouldShowPromo
    }
    
    func updateDuckDuckGoVisibility() {
        let isVisible = shouldShowDuckDuckGoCallout()
        let heightOfCallout = ddgButton.systemLayoutSizeFitting(UIView.layoutFittingExpandedSize).height + (UI.searchEngineCalloutPadding * 2.0)
        collection.contentInset.bottom = isVisible ? heightOfCallout : 0
        ddgButton.isHidden = !isVisible
    }
}

// MARK: - Delegates
extension FavoritesViewController: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let fav = dataSource.favoriteBookmark(at: indexPath)
        
        guard let urlString = fav?.url else { return }
        
        delegate?.didSelect(input: urlString)
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let width = collection.frame.width
        let padding: CGFloat = traitCollection.horizontalSizeClass == .compact ? 6 : 20
        
        let cellWidth = floor(width - padding) / CGFloat(dataSource.columnsPerRow)
        // The tile's height is determined the aspect ratio of the thumbnails width. We also take into account
        // some padding between the title and the image.
        let cellHeight = floor(cellWidth / (CGFloat(FavoriteCell.imageAspectRatio) - 0.1))
        
        return CGSize(width: cellWidth, height: cellHeight)
    }
    
    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard let favoriteCell = cell as? FavoriteCell else { return }
        favoriteCell.delegate = self
    }
}

extension FavoritesViewController: FavoriteCellDelegate {
    func editFavorite(_ favoriteCell: FavoriteCell) {
        guard let indexPath = collection.indexPath(for: favoriteCell),
            let fav = dataSource.frc?.fetchedObjects?[indexPath.item] else { return }
        
        let actionSheet = UIAlertController(title: fav.displayTitle, message: nil, preferredStyle: .actionSheet)
        
        let deleteAction = UIAlertAction(title: Strings.removeFavorite, style: .destructive) { _ in
            fav.delete()
            
            // Remove cached icon.
            if let urlString = fav.url, let url = URL(string: urlString) {
                ImageCache.shared.remove(url, type: .square)
            }
            
            self.dataSource.isEditing = false
        }
        
        let editAction = UIAlertAction(title: Strings.editFavorite, style: .default) { _ in
            guard let title = fav.displayTitle, let urlString = fav.url else { return }
            
            let editPopup = UIAlertController.userTextInputAlert(title: Strings.editBookmark, message: urlString,
                                                                 startingText: title, startingText2: fav.url,
                                                                 placeholder2: urlString,
                                                                 keyboardType2: .URL) { callbackTitle, callbackUrl in
                                                                    if let cTitle = callbackTitle, !cTitle.isEmpty, let cUrl = callbackUrl, !cUrl.isEmpty {
                                                                        if URL(string: cUrl) != nil {
                                                                            fav.update(customTitle: cTitle, url: cUrl)
                                                                        }
                                                                    }
                                                                    self.dataSource.isEditing = false
            }
            
            self.present(editPopup, animated: true)
        }
        
        let cancelAction = UIAlertAction(title: Strings.cancelButtonTitle, style: .cancel, handler: nil)
        
        actionSheet.addAction(editAction)
        actionSheet.addAction(deleteAction)
        actionSheet.addAction(cancelAction)
        
        if UIDevice.current.userInterfaceIdiom == .pad {
            actionSheet.popoverPresentationController?.permittedArrowDirections = .any
            actionSheet.popoverPresentationController?.sourceView = favoriteCell
            actionSheet.popoverPresentationController?.sourceRect = favoriteCell.bounds
            present(actionSheet, animated: true)
        } else {
            present(actionSheet, animated: true) {
                self.dataSource.isEditing = false
            }
        }
    }

}
