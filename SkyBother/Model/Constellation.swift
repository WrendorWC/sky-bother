import Foundation

/// The catalogue stores each target's constellation as its official IAU
/// three-letter abbreviation ("And", "Cas", "Tau"...) — the standard form
/// in every astronomical catalog this app's data comes from, and the right
/// thing to store. It's a bad thing to *show* someone, though, so this maps
/// all 88 back to a real name for display. The list itself hasn't changed
/// since the IAU formalized constellation boundaries in 1930.
///
/// Serpens is the one constellation split into two disconnected regions on
/// the sky, and OpenNGC gives its two halves their own non-standard codes
/// rather than the single official "Ser" — confirmed against real entries:
/// "Se1" objects fall at the right ascension of Serpens Caput (the head),
/// "Se2" at Serpens Cauda (the tail).
enum Constellation {
    static let fullNames: [String: String] = [
        "Se1": "Serpens Caput", "Se2": "Serpens Cauda",
        "And": "Andromeda", "Ant": "Antlia", "Aps": "Apus", "Aqr": "Aquarius",
        "Aql": "Aquila", "Ara": "Ara", "Ari": "Aries", "Aur": "Auriga",
        "Boo": "Boötes", "Cae": "Caelum", "Cam": "Camelopardalis", "Cnc": "Cancer",
        "CVn": "Canes Venatici", "CMa": "Canis Major", "CMi": "Canis Minor",
        "Cap": "Capricornus", "Car": "Carina", "Cas": "Cassiopeia", "Cen": "Centaurus",
        "Cep": "Cepheus", "Cet": "Cetus", "Cha": "Chamaeleon", "Cir": "Circinus",
        "Col": "Columba", "Com": "Coma Berenices", "CrA": "Corona Australis",
        "CrB": "Corona Borealis", "Crv": "Corvus", "Crt": "Crater", "Cru": "Crux",
        "Cyg": "Cygnus", "Del": "Delphinus", "Dor": "Dorado", "Dra": "Draco",
        "Equ": "Equuleus", "Eri": "Eridanus", "For": "Fornax", "Gem": "Gemini",
        "Gru": "Grus", "Her": "Hercules", "Hor": "Horologium", "Hya": "Hydra",
        "Hyi": "Hydrus", "Ind": "Indus", "Lac": "Lacerta", "Leo": "Leo",
        "LMi": "Leo Minor", "Lep": "Lepus", "Lib": "Libra", "Lup": "Lupus",
        "Lyn": "Lynx", "Lyr": "Lyra", "Men": "Mensa", "Mic": "Microscopium",
        "Mon": "Monoceros", "Mus": "Musca", "Nor": "Norma", "Oct": "Octans",
        "Oph": "Ophiuchus", "Ori": "Orion", "Pav": "Pavo", "Peg": "Pegasus",
        "Per": "Perseus", "Phe": "Phoenix", "Pic": "Pictor", "Psc": "Pisces",
        "PsA": "Piscis Austrinus", "Pup": "Puppis", "Pyx": "Pyxis", "Ret": "Reticulum",
        "Sge": "Sagitta", "Sgr": "Sagittarius", "Sco": "Scorpius", "Scl": "Sculptor",
        "Sct": "Scutum", "Ser": "Serpens", "Sex": "Sextans", "Tau": "Taurus",
        "Tel": "Telescopium", "Tri": "Triangulum", "TrA": "Triangulum Australe",
        "Tuc": "Tucana", "UMa": "Ursa Major", "UMi": "Ursa Minor", "Vel": "Vela",
        "Vir": "Virgo", "Vol": "Volans", "Vul": "Vulpecula"
    ]

    /// Falls back to the raw abbreviation if it's ever missing rather than
    /// showing nothing — shouldn't happen with a complete 88-entry table,
    /// but an unrecognized value is still better shown than hidden.
    static func fullName(for abbreviation: String) -> String {
        fullNames[abbreviation] ?? abbreviation
    }
}
