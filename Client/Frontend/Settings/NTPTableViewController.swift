// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import Foundation
import Static
import BraveShared
import Shared

class NTPTableViewController: TableViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Hides unnecessary empty rows
        tableView.tableFooterView = UIView()
        
        navigationItem.title = Strings.newTabPageSettingsTitle
        tableView.accessibilityIdentifier = "NewTabPageSettings.tableView"
        dataSource.sections = [section]
    }
    
    private lazy var section: Section = {
        var rows = [Row.boolRow(title: Strings.newTabPageSettingsAutoOpenKeyboard,
                             option: Preferences.NewTabPage.autoOpenKeyboard)]
        return Section(rows: rows)
    }()
}
