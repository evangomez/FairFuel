import Foundation

/// Combined EPA MPG estimates for common US vehicles.
/// 0 = electric (no fuel consumption).
enum VehicleDatabase {

    static let mpgByMakeModel: [String: [String: Int]] = [
        "Acura":          ["ILX": 31, "MDX": 27, "RDX": 28, "TLX": 29],
        "Audi":           ["A3": 32, "A4": 30, "A5": 27, "A6": 27, "Q3": 28, "Q5": 27, "Q7": 22, "Q8": 21, "e-tron": 0],
        "BMW":            ["2 Series": 30, "3 Series": 28, "4 Series": 26, "5 Series": 25, "7 Series": 22,
                           "X1": 29, "X3": 27, "X5": 22, "X7": 20, "M3": 19, "M4": 18],
        "Buick":          ["Encore": 32, "Enclave": 22, "Envision": 28],
        "Cadillac":       ["CT4": 30, "CT5": 27, "Escalade": 17, "XT4": 30, "XT5": 27, "XT6": 24],
        "Chevrolet":      ["Colorado": 22, "Equinox": 31, "Malibu": 29, "Silverado 1500": 23,
                           "Silverado 2500": 17, "Spark": 33, "Suburban": 19, "Tahoe": 20,
                           "Traverse": 24, "Trax": 32],
        "Chrysler":       ["Pacifica": 26, "Pacifica Hybrid": 32],
        "Dodge":          ["Challenger": 20, "Charger": 22, "Durango": 21],
        "Ford":           ["Bronco": 21, "Bronco Sport": 26, "Escape": 30, "Explorer": 24,
                           "F-150": 24, "F-250": 17, "Maverick": 33, "Mustang": 21,
                           "Mustang Mach-E": 0, "Ranger": 24],
        "GMC":            ["Acadia": 24, "Canyon": 22, "Sierra 1500": 23, "Sierra 2500": 17,
                           "Terrain": 28, "Yukon": 19],
        "Honda":          ["Accord": 33, "Civic": 36, "CR-V": 32, "HR-V": 30,
                           "Odyssey": 22, "Passport": 25, "Pilot": 24, "Ridgeline": 23],
        "Hyundai":        ["Accent": 38, "Elantra": 37, "Ioniq 5": 0, "Ioniq 6": 0,
                           "Kona": 32, "Palisade": 24, "Santa Cruz": 25,
                           "Santa Fe": 26, "Sonata": 32, "Tucson": 29],
        "Infiniti":       ["Q50": 26, "Q60": 22, "QX50": 27, "QX60": 23, "QX80": 17],
        "Jeep":           ["Cherokee": 26, "Compass": 27, "Gladiator": 21,
                           "Grand Cherokee": 23, "Renegade": 29, "Wrangler": 20],
        "Kia":            ["Carnival": 22, "EV6": 0, "Forte": 33, "K5": 32,
                           "Sorento": 26, "Soul": 29, "Sportage": 30,
                           "Stinger": 25, "Telluride": 24],
        "Lexus":          ["ES": 31, "GX": 19, "IS": 29, "LX": 16, "NX": 33, "RX": 30, "UX": 37],
        "Lincoln":        ["Aviator": 23, "Corsair": 29, "Navigator": 17],
        "Mazda":          ["CX-30": 31, "CX-5": 30, "CX-50": 29, "CX-9": 24,
                           "Mazda3": 32, "Mazda6": 28, "MX-5 Miata": 32],
        "Mercedes-Benz":  ["C-Class": 27, "E-Class": 24, "GLC": 27, "GLE": 22, "GLS": 21, "S-Class": 21],
        "Nissan":         ["Altima": 32, "Armada": 15, "Frontier": 22, "Kicks": 33,
                           "Leaf": 0, "Maxima": 26, "Murano": 28, "Pathfinder": 25,
                           "Rogue": 33, "Sentra": 35, "Titan": 17, "Versa": 39],
        "Ram":            ["1500": 22, "2500": 17, "ProMaster": 19],
        "Subaru":         ["Ascent": 26, "BRZ": 29, "Crosstrek": 31, "Forester": 30,
                           "Impreza": 31, "Legacy": 30, "Outback": 30, "WRX": 25],
        "Tesla":          ["Model 3": 0, "Model S": 0, "Model X": 0, "Model Y": 0],
        "Toyota":         ["4Runner": 17, "Avalon": 28, "Camry": 32, "Corolla": 35,
                           "GR86": 29, "Highlander": 24, "Land Cruiser": 16,
                           "Prius": 52, "RAV4": 30, "Sequoia": 19,
                           "Sienna": 35, "Tacoma": 21, "Tundra": 19, "Venza": 40],
        "Volkswagen":     ["Atlas": 24, "Golf": 32, "ID.4": 0, "Jetta": 35,
                           "Taos": 29, "Tiguan": 27],
        "Volvo":          ["S60": 30, "S90": 27, "V60": 30, "XC40": 29, "XC60": 27, "XC90": 24],
    ]

    static var makes: [String] { mpgByMakeModel.keys.sorted() }

    static func models(for make: String) -> [String] {
        (mpgByMakeModel[make] ?? [:]).keys.sorted()
    }

    static func mpg(make: String, model: String) -> Int? {
        mpgByMakeModel[make]?[model]
    }
}
