# The narration, beat by beat, in order. Stress marks as in the telescope film:
# `[word](+2)` stresses a word, `[word](-1)` softens it (KokoroRunner).
# SCRIPT.md describes the pictures; the words live here.

const BEATS = [
    "a0_first_picture" => [
        "How do you photograph a black hole, when not even [light](+2) can escape? In 2019, astronomers did it: a glowing ring around a dark shadow.",
        "They linked telescopes across the [whole](+2) Earth, then computed the picture from their recordings. Here's how that works.",
    ],
    "a1_black_hole" => [
        "A black hole is a place where gravity is so strong that [nothing](+2) can get out, not even light. Its edge is called the event horizon.",
        "Around it, gas swirls in a flat disk, so hot that it glows. If light travelled in straight lines, it would look like this.",
        "But gravity [bends](+2) light. Light from the back of the disk is bent over the top of the black hole, and under it. So we see the back of the disk, too.",
        "Light that comes too close falls in. That leaves a dark shadow, more than [twice](+2) as wide as the black hole itself, ringed by a thin, bright circle: light that looped around the hole before escaping. That's the photon ring.",
        "The gas races around at close to half the speed of light. The side rushing [towards](+2) us looks brighter. The side moving away looks dimmer.",
        "We see the black hole in M eighty-seven almost from above. From here, it's a glowing ring around a dark middle.",
    ],
    "a2_two_numbers" => [
        "Scientists love black holes because they're surprisingly simple. To describe a cat, you'd need a long list: colour, size, weight, personality, favourite food.",
        "A black hole needs just [two](+2) numbers: how heavy it is, and how fast it spins. Measure its picture, and you can learn both.",
    ],
    "a3_tiny" => [
        "The black hole in the galaxy M eighty-seven is enormous: its shadow is bigger than our whole solar system. But it's fifty-five million light-years away.",
        "Seen from Earth, it looks as small as an orange on the Moon.",
    ],
    "a4_giant_telescope" => [
        "So how do you see something that tiny? A telescope's sharpness depends on two things: the wavelength of the light, and the width of its opening.",
        "These black holes are best seen in radio light, about a millimetre long. To see an orange on the Moon at that wavelength, the opening has to be about as wide as the [Earth](+2).",
    ],
    "a5_why_radio" => [
        "But wait. Visible light waves are thousands of times shorter than radio waves. With visible light, a telescope a few kilometres wide would do. So why radio?",
        "Because no single telescope is that big, the giant telescope has to be stitched together from many. And that only works if each one records the light wave [itself](+2), every single wiggle, so a computer can combine the recordings later.",
        "Electronics can keep up with radio waves and record them. Visible light wiggles five hundred trillion times a second: far too fast for any machine.",
        "The wavelength also matters for another reason. At longer radio wavelengths, the glowing gas around the black hole hides the view, like a thick fog.",
        "At one point three millimetres, we can see through that gas. The fog clears, revealing the ring.",
        "Then there is a separate obstacle: our own atmosphere. Water vapour absorbs this light. Putting telescopes high on dry mountains leaves less damp air in the way.",
    ],
    "b0_stations" => [
        "So astronomers point radio telescopes all over the world at the [same](+2) black hole, at the same moment: in Hawaii, Arizona, Mexico, Chile, Spain, France and Greenland.",
        "Together they act like pieces of one giant dish. This is the Event Horizon Telescope.",
    ],
    "b1_recording" => [
        "Each telescope records the radio signal itself. A machine measures it four [billion](+2) times every second, in several channels at once.",
        "To save space, each measurement keeps just two bits: one of only four values. That sounds crude, but the black hole's signal is buried in noise anyway. It only shows up later, when billions of measurements are compared.",
        "Even so, that's four gigabytes every second: enough to fill a laptop in about four minutes. In one night, each telescope records about a hundred terabytes.",
        "The spinning hard disks used for these observations could not individually keep up. So each recorder spread the data across thirty-two disks in [parallel](+2).",
    ],
    "b2_clocks" => [
        "Later, the recordings from different telescopes have to be lined up, wiggle on wiggle. At one point three millimetres, one wiggle lasts just four [trillionths](+2) of a second.",
        "So every telescope has an atomic clock, a hydrogen maser. It's so steady that it would take millions of years to be off by a single second. In ten seconds, it drifts by less than a twentieth of a wiggle.",
        "With worse clocks, the waves would slide out of step. Instead of adding up, they would [blur](+2) away.",
    ],
    "b3_correlator" => [
        "The drives hold far too much to send over the internet: it would take about a year. So they're flown, by plane, to two supercomputers, in Germany and in the United States.",
        "There, for every pair of telescopes, the two recordings are lined up and compared. The black hole's light is the part they have in [common](+2). Everything else is noise, and averages away.",
    ],
    "b4_one_note" => [
        "So what does comparing two recordings give us? Not a picture. Each [pair](+2) of telescopes measures just one thing: how strongly one stripe pattern is hidden in the picture.",
        "To see where the stripes come from, think of light as a wave. From straight ahead, it reaches both telescopes at the same moment. From a slightly different direction, it travels farther to one telescope, shifting the two wiggles out of step.",
        "Half an extra wavelength puts a peak against a trough. One whole wavelength brings them back into step. Across the sky, the match goes up and down: that's the stripe pattern.",
        "Now move the telescopes farther apart. For the same small change in direction, the extra distance changes more. So the waves go in and out of step faster across the sky, making finer stripes. A close pair gives wide stripes: the coarse shape. A far pair gives fine stripes: the small details.",
        "Think of the picture as a piece of music. Every pair of telescopes hears just [one](+2) note of it.",
        "Put enough of these stripes together, each with its own strength, and they add up to the [whole](+2) picture. Wide stripes give the rough shape, fine ones the sharp details.",
    ],
    "b5_earth_turns" => [
        "With only a handful of sites, that's only a few notes. But the Earth turns, and as it does, each pair sees the black hole from a slightly different angle, and hears a slightly different note.",
        "Over one night, the notes trace out these curves. Still, most of the music is missing.",
    ],
    "b6_guess_the_song" => [
        "From just these notes, many different pictures would fit. It's like guessing a song from a handful of notes.",
        "So the picture isn't measured directly. It has to be [inferred](+2): found by computer, as the picture that best explains the notes.",
    ],
    "b7_cleaning" => [
        "But first, the measurements must be cleaned. Above each telescope the air wobbles, and delays the waves a little, differently every few seconds. That slides each pair's stripes back and forth.",
        "Here's a clever trick. Take three telescopes, A, B and C. The air above A pushes the stripes of pair A B forward, and those of pair C A back, by exactly as much. So around the triangle, every wobble is counted once forward and once back, and cancels out. What's left belongs to the black hole.",
        "Now look at the scale of the data. Across all the targets observed that week, the telescopes recorded about four petabytes. Let this whole square stand for those recordings.",
        "Zoom in to one terabyte, about a laptop drive. Four thousand of these fit inside the big square.",
        "Inside that, one gigabyte. A thousand gigabytes make one terabyte.",
        "And here are four and a half megabytes. After comparing recordings, selecting M eighty-seven and calibrating the measurements, this is the tiny data set used to reconstruct its picture. Less data than a typical phone photo.",
        "If all the recordings filled this whole square, that data would be a speck, far too small to see.",
    ],
    "b8_imaging" => [
        "With those measurements ready, four teams independently worked out what the picture could look like. Each used its own method, without seeing the others' results. After seven weeks, they compared. All four had found a ring.",
        "That ring is also a ruler. In general relativity, a heavier black hole casts a larger shadow. So its size tells us how much mass is hidden inside.",
        "First, measure how wide the ring looks in the sky. Combine that with the galaxy's distance, about fifty-five million light-years, to find its physical size.",
        "Then compare with simulations of glowing gas around black holes. They connect the bright ring to the shadow's size, and that size to the mass. The result is about six and a half billion times the mass of our Sun. We have weighed an object that emits no light of its own.",
    ],
    "c0_many_pictures" => [
        "Older methods gave a single picture, and astronomers argued about which parts of it were real.",
        "A better way is to find [all](+2) the pictures that fit the data, and how likely each one is. Where they agree, we can trust the picture. Where they disagree, we know we're unsure.",
    ],
    "c1_julia" => [
        "But that means trying out millions of pictures, and it used to take about a week on a thousand processors.",
        "Written in Julia, the same kind of analysis, a package called Comrade, takes about half an hour on [one](+2), with forty times more detail in the model.",
    ],
    "c2_space" => [
        "To see sharper, we need an even bigger telescope, bigger than the Earth. The Black Hole Explorer will put a radio dish in space.",
        "Its notes reach much higher, fine enough to see the thin photon ring itself. And its data will be turned into pictures with Julia.",
    ],
    "c3_outro" => [
        "A picture of a black hole isn't taken. It's [computed](+2): from a few notes, heard by telescopes all over the Earth.",
        "Better software means better science, and sharper pictures of the edge of the universe.",
    ],
]
