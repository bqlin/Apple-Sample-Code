/*
Copyright (C) 2017 Apple Inc. All Rights Reserved.
See LICENSE.txt for this sample’s licensing information

Abstract:
Data source of city names.
*/

import Foundation
import UIKit

class CitiesDataSource: NSObject, UITableViewDataSource
{
	fileprivate var cities: [String] = []
	
	override init() {
		super.init()
		
		let citiesJSONURL =
			URL(fileURLWithPath: Bundle.main.path(forResource: "Cities", ofType: "json")!)
		do {
			let citiesJSONData = try Data(contentsOf: citiesJSONURL)
			let jsonObject = try JSONSerialization.jsonObject(with: citiesJSONData,
															  options: JSONSerialization.ReadingOptions(rawValue: UInt(0)))
			if let jsonCities = jsonObject as? [String] {
				cities = jsonCities
			}
		}
		catch {
			//..
		}
	}
	
	@objc func city(index: Int) -> String {
		return cities[index]
	}
	
	// MARK: - UITableViewDataSource

	func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return cities.count
	}
	
	func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let flavor = cities[indexPath.row]
		let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
		cell.textLabel?.text = flavor
		return cell
	}
	
}
