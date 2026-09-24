import Foundation

/// A few things worth knowing about the targets people image most — what
/// they are, what makes them remarkable, and what matters when imaging them.
/// Written by hand for the showpieces; everything else falls back to the
/// Wikipedia summary in `TargetFactCatalog`. Distances are rounded, and
/// hedged where published estimates disagree.
enum CuratedFacts {
    static func facts(for designation: String) -> [String] {
        table[designation] ?? []
    }

    private static let table: [String: [String]] = [
        // MARK: Messier
        "M1": [
            "The remains of a supernova Chinese astronomers recorded in 1054 — bright enough to see in daylight for weeks.",
            "At its heart is a pulsar spinning about 30 times a second, powering the nebula's blue glow.",
            "Around 6,500 light-years away and still expanding at about 1,500 km/s."
        ],
        "M3": [
            "About half a million stars, some 34,000 light-years away.",
            "Holds more known variable stars than any other globular cluster — over 200 RR Lyrae stars."
        ],
        "M7": [
            "Described by Ptolemy around 130 AD, which is why it carries his name.",
            "Large and bright: about a degree across, so it suits a wide field."
        ],
        "M8": [
            "A huge star-forming cloud about 4,000 light-years away, visible to the naked eye from a dark site.",
            "Its brightest core is the Hourglass Nebula, sculpted by the young star Herschel 36.",
            "Dark Bok globules scattered across it are clouds that may still collapse into stars."
        ],
        "M11": [
            "One of the richest open clusters known, with nearly 3,000 stars.",
            "Its bright stars form a V that reminded observers of a flight of wild ducks."
        ],
        "M13": [
            "Several hundred thousand stars packed into a ball about 145 light-years across, some 22,000 light-years away.",
            "The Arecibo radio message was beamed toward it in 1974 — it will arrive in about 25,000 years."
        ],
        "M16": [
            "Home of the Pillars of Creation, made famous by Hubble in 1995.",
            "About 7,000 light-years away, lit by the young cluster NGC 6611 inside it.",
            "Narrowband brings out the pillars; they sit near the centre of the nebula."
        ],
        "M17": [
            "One of the brightest and most massive star-forming regions in the galaxy, about 5,500 light-years away.",
            "Also called the Swan or Checkmark Nebula — its bright bar looks like a swan on the water."
        ],
        "M20": [
            "Three nebulae in one: red emission, blue reflection, and the dark lanes that split it into three lobes.",
            "Its young stars are only a few hundred thousand years old."
        ],
        "M24": [
            "Not a true cluster but a window through the dust into a distant spiral arm, thousands of stars deep.",
            "About 1.5° long — one of the few Messier objects that needs a wide field."
        ],
        "M27": [
            "The first planetary nebula ever found, by Charles Messier in 1764.",
            "A dying Sun-like star's cast-off gas, about 1,300 light-years away and roughly 10,000 years old.",
            "Very bright in OIII — a dual-band filter shows its faint outer halo."
        ],
        "M31": [
            "The nearest large galaxy, about 2.5 million light-years away — the most distant thing most people can see with the naked eye.",
            "About 3° long in images, six full Moons across.",
            "Heading toward the Milky Way; the two should merge in roughly 4–5 billion years.",
            "Its companions M32 and M110 fit in the same frame."
        ],
        "M33": [
            "The third-largest galaxy in the Local Group, about 2.7 million light-years away.",
            "Its light is spread thin, so it's hard to see by eye despite its magnitude — a long exposure pays off.",
            "NGC 604, a star-forming region inside it, is over 1,000 light-years across."
        ],
        "M42": [
            "The nearest large star-forming region, about 1,350 light-years away — the middle 'star' of Orion's sword.",
            "The Trapezium, four young stars at its core, lights the whole nebula.",
            "Huge brightness range: short exposures keep the core from burning out while long ones pull in the wings."
        ],
        "M43": [
            "Part of the Orion Nebula, separated from it only by a lane of dark dust.",
            "Lit by a single young star, NU Orionis."
        ],
        "M44": [
            "Known since antiquity; Galileo resolved it into about 40 stars with his first telescope.",
            "About 600 light-years away and over a degree across."
        ],
        "M45": [
            "About 440 light-years away and roughly 100 million years old.",
            "The blue glow isn't leftover from the stars' birth — they're drifting through an unrelated dust cloud.",
            "The Subaru logo is the Pleiades; 'Subaru' is its Japanese name."
        ],
        "M51": [
            "The first galaxy seen to have a spiral shape, drawn by Lord Rosse in 1845.",
            "Its companion NGC 5195 is passing behind it, pulling at one arm.",
            "About 30 million light-years away."
        ],
        "M57": [
            "A shell of gas from a dying star, about 2,500 light-years away.",
            "Small — under 2 arcminutes — so it rewards focal length.",
            "The central white dwarf is around magnitude 15, a nice test for your setup."
        ],
        "M63": [
            "A 'flocculent' spiral: its arms are patchy tufts rather than two clean arms.",
            "About 29 million light-years away."
        ],
        "M64": [
            "Named for the dark dust band in front of its bright core.",
            "Its outer gas rotates the opposite way to its inner gas — likely from swallowing another galaxy."
        ],
        "M74": [
            "A near-perfect face-on spiral about 32 million light-years away.",
            "Called the Phantom for its low surface brightness — one of the hardest Messier galaxies to see by eye."
        ],
        "M76": [
            "One of the faintest Messier objects, a small planetary nebula in Perseus.",
            "Its two lobes look like a miniature Dumbbell Nebula."
        ],
        "M81": [
            "A bright grand-design spiral about 12 million light-years away.",
            "It pairs with M82 in the same field, less than a degree apart."
        ],
        "M82": [
            "A starburst galaxy: a close pass by M81 set off a burst of star formation.",
            "Red plumes of hydrogen blasting out of its disk show well in Hα."
        ],
        "M83": [
            "A barred spiral about 15 million light-years away.",
            "One of the most prolific galaxies for supernovae — several have been seen in it."
        ],
        "M87": [
            "A giant elliptical at the heart of the Virgo Cluster.",
            "Its black hole was the first ever imaged, by the Event Horizon Telescope in 2019.",
            "A jet thousands of light-years long streams from its core."
        ],
        "M97": [
            "Two dark patches give this planetary nebula its owl's eyes.",
            "Faint and OIII-rich; M108 is less than a degree away."
        ],
        "M101": [
            "A large face-on spiral about 21 million light-years away, nearly half a degree across.",
            "Two bright supernovae in recent years: SN 2011fe and SN 2023ixf."
        ],
        "M104": [
            "An almost edge-on galaxy with a striking dust lane and a huge bright bulge.",
            "About 30 million light-years away."
        ],

        // MARK: Nebulae
        "NGC 7000": [
            "Named for its resemblance to the continent — the 'Gulf of Mexico' is a dark dust cloud.",
            "About 2° across, so it wants a wide field; the Cygnus Wall is its brightest edge.",
            "Shines mostly in Hα; a dual-band filter makes it an easy target even from town."
        ],
        "IC 5070": [
            "Part of the same cloud as the North America Nebula, split from it by the dark cloud LDN 935.",
            "Its 'head' has pillars and bright rims where young stars are eroding the gas."
        ],
        "NGC 6960": [
            "The western half of the Veil, the remains of a star that exploded 10,000–20,000 years ago.",
            "It runs right past the bright star 52 Cygni, earning it the name Witch's Broom.",
            "Glows strongly in both Hα and OIII."
        ],
        "NGC 6992": [
            "The eastern half of the Veil supernova remnant, about 2,400 light-years away.",
            "The whole loop is about 3° across; the eastern arc is the brightest part.",
            "Its filaments are shock fronts still expanding into space."
        ],
        "NGC 6888": [
            "Blown by the fierce wind of the Wolf-Rayet star WR 136 slamming into gas it shed earlier.",
            "A faint OIII shell surrounds the brighter Hα crescent — worth long narrowband integration."
        ],
        "NGC 7635": [
            "A bubble about 7 light-years across, blown by the wind of one massive star.",
            "Roughly 7,000 light-years away in Cassiopeia."
        ],
        "NGC 281": [
            "Its dark notch looks like Pac-Man's mouth.",
            "Dark Bok globules inside it are sites of future star formation."
        ],
        "IC 1805": [
            "About 7,500 light-years away, carved by the young cluster Melotte 15 at its centre.",
            "Pairs with the Soul Nebula next door — together the Heart and Soul."
        ],
        "IC 1848": [
            "The 'Soul' of the Heart and Soul pair, about 7,500 light-years away.",
            "Rich in pillars and bright-rimmed clouds shaped by its young stars."
        ],
        "NGC 1499": [
            "About 2.5° long — it really does look like California.",
            "Lit by the hot star Xi Persei; faint by eye but bright in Hα."
        ],
        "IC 434": [
            "The Horsehead itself is a dark dust cloud, Barnard 33, silhouetted against glowing hydrogen.",
            "About 1,400 light-years away, just below Alnitak in Orion's belt.",
            "The Flame Nebula sits close by in the same field."
        ],
        "NGC 2024": [
            "Right beside Alnitak, whose glare is the challenge — the dark lanes are dust in front of glowing gas.",
            "A young cluster hides inside, visible only in infrared."
        ],
        "NGC 2237": [
            "A flower of gas about 1.3° across, 5,000 light-years away.",
            "The cluster NGC 2244 at its centre has blown out the hollow middle."
        ],
        "NGC 2264": [
            "Home to the Christmas Tree Cluster, the Cone Nebula and the Fox Fur Nebula.",
            "The 'tree' looks upside down in most images — its star is at the bottom."
        ],
        "IC 443": [
            "A supernova remnant beside the star Propus in Gemini, about 5,000 light-years away.",
            "Its age is uncertain — estimates range from 3,000 to 30,000 years."
        ],
        "IC 405": [
            "Lit by AE Aurigae, a runaway star flung from the Orion region about 2 million years ago.",
            "Mixes red emission with blue reflection nebulosity near the star."
        ],
        "IC 410": [
            "The 'tadpoles' are two streamers of gas about 10 light-years long, pointing away from the central cluster.",
            "Much farther than it looks — about 12,000 light-years."
        ],
        "NGC 2359": [
            "A bubble blown by the Wolf-Rayet star WR 7, shaped like a winged helmet.",
            "Strong in OIII; a dual-band filter brings out its fine structure."
        ],
        "NGC 2392": [
            "A small, bright planetary nebula nicknamed the Clown-face or Eskimo.",
            "Its central star is bright enough to see easily — around magnitude 10."
        ],
        "NGC 7293": [
            "One of the nearest planetary nebulae, about 650 light-years away.",
            "About half the Moon's width — large but faint, so it needs long exposures.",
            "Hubble revealed thousands of 'cometary knots' in its inner ring."
        ],
        "NGC 7009": [
            "Named by Lord Rosse for thin extensions either side that look like Saturn's rings.",
            "Small and bright, with a strong green-blue OIII colour."
        ],
        "NGC 6543": [
            "One of the most intricate planetary nebulae known — Hubble found at least 11 shells.",
            "Sits almost at the north ecliptic pole, so it's up all year from the north."
        ],
        "NGC 7380": [
            "A young cluster wrapped in the nebula it formed from, about 7,000 light-years away.",
            "Its outline looks like a wizard in a pointed hat."
        ],
        "IC 1396": [
            "A large region about 3° across in Cepheus.",
            "The Elephant's Trunk is a dense dark globule still forming stars.",
            "The deep-red Garnet Star, Mu Cephei, sits at its northern edge."
        ],
        "Sh2-155": [
            "A faint glowing cloud with a dark 'mouth' that gives it the look of a cave.",
            "Part of a large complex of dust and gas in Cepheus."
        ],
        "NGC 7023": [
            "A reflection nebula lit by the star HD 200775 — blue, not red.",
            "Surrounded by dark dust, so it's a broadband target: skip the narrowband filter."
        ],
        "NGC 3372": [
            "Four times the size of the Orion Nebula and one of the largest in the sky.",
            "Home to Eta Carinae, among the most massive and unstable stars known.",
            "Visible only from the southern hemisphere."
        ],
        "NGC 2070": [
            "The most active star-forming region in the Local Group, inside the Large Magellanic Cloud.",
            "Its central cluster R136 holds the most massive stars known."
        ],
        "NGC 6334": [
            "A busy nursery of massive stars about 5,500 light-years away.",
            "Its round lobes look like a cat's footprint."
        ],
        "IC 5146": [
            "A glowing cloud at the end of a long dark nebula, Barnard 168.",
            "A young cluster sits at its centre."
        ],
        "NGC 1514": [
            "William Herschel found it in 1790; seeing one star wrapped in glow convinced him some nebulae were gas, not distant stars.",
            "Infrared images show two faint rings around it."
        ],

        // MARK: Galaxies
        "NGC 6946": [
            "Ten supernovae have been seen in it in about a century — more than in any other galaxy.",
            "It lies behind Milky Way dust, which dims and reddens it."
        ],
        "NGC 253": [
            "A dusty starburst galaxy about 11 million light-years away, one of the brightest in the sky.",
            "Discovered by Caroline Herschel in 1783."
        ],
        "NGC 4565": [
            "A classic edge-on spiral with a razor-thin dust lane.",
            "About 40 million light-years away."
        ],
        "NGC 4631": [
            "An edge-on galaxy whose shape suggests a whale; the small companion NGC 4627 is its 'calf'.",
            "Its disk is distorted by nearby galaxies."
        ],
        "NGC 3628": [
            "Part of the Leo Triplet with M65 and M66 — all three fit in one field.",
            "A long faint tidal tail stretches from it, pulled out by its neighbours."
        ],
        "NGC 4038": [
            "Two galaxies in the middle of colliding, with long tails of stars thrown out by the collision."
        ],
        "NGC 6822": [
            "A dwarf galaxy in the Local Group, about 1.6 million light-years away.",
            "Its low surface brightness makes it a test of dark skies."
        ],
        "NGC 5128": [
            "The nearest radio galaxy, about 12 million light-years away.",
            "The dark lane across it is from a galaxy it swallowed."
        ],
        "LMC": [
            "A satellite galaxy of the Milky Way, about 160,000 light-years away.",
            "Supernova 1987A, the closest seen in modern times, went off here."
        ],
        "SMC": [
            "A small satellite galaxy about 200,000 light-years away, visible to the naked eye from the south."
        ],

        // MARK: Clusters
        "NGC 869": [
            "Half of the Double Cluster; its twin NGC 884 sits right beside it.",
            "About 7,500 light-years away and only around 13 million years old.",
            "Visible to the naked eye as a hazy patch in Perseus."
        ],
        "NGC 5139": [
            "The largest globular cluster in the Milky Way, with around 10 million stars.",
            "It may be the core of a small galaxy the Milky Way tore apart."
        ],
        "NGC 104": [
            "The second-brightest globular cluster, about 15,000 light-years away.",
            "Sits beside the Small Magellanic Cloud in the sky."
        ],
        "M34": [
            "An open cluster of about 100 stars, roughly the Moon's width across.",
            "About 1,500 light-years away."
        ],
        "M39": [
            "A loose, bright open cluster about 1,000 light-years away — nearly a degree across."
        ],
        "NGC 752": [
            "An old open cluster, over a billion years old.",
            "Wide and scattered — nearly a degree across."
        ]
    ]
}
