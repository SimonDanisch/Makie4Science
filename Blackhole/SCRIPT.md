# How do you photograph a black hole?

An explainer after Paul Tiede's JuliaCon keynote "Resolving the Edge of the
Universe: Imaging Black Holes with Julia" (`keynote/JuliaCon_Keynote.pptx`).
Same style as the telescope film (`../sharpness`): one idea per beat, every
named thing labelled when it is said, a 12-year-old can follow. Narration is
English, spoken by Kokoro (`af_heart`), stress marks as in the telescope film.

The thread: a black hole is tiny in the sky; seeing it needs a telescope the
size of the Earth; we can only build one in pieces, which measure a few
"notes" of the picture; turning those notes into a picture, with honest error
bars, is a computing problem, and that is where Julia comes in.

Visuals are our own Makie scenes, computed where possible (Fourier samples of
a model ring, real EHT station positions, uv tracks from the Earth's rotation).
The cat comparison reuses the Niki & Nala photo from keynote slides 3–4,
with the original credit. Other visuals are recreated rather than slide images.

## Act 1: what we want to see

**a0 · The first picture** (the hook)
Visual: a glowing, blurry orange ring on black, slowly sharpening into view.
> "In 2019, astronomers showed the world something no one had ever seen: a
> picture of a black hole. A blurry orange ring, around a dark centre."
> "To take it, they needed a telescope as big as the [whole](+2) Earth, and a lot
> of clever computing. This video is about how that works."

**a1 · What a black hole is**
Visual: 3D model, slow orbit. Black sphere, a glowing disk of gas, a thin
bright ring. Labels appear as named.
> "A black hole is a place where gravity is so strong that [nothing](+2) can get
> out, not even light. Its edge is called the event horizon."
> "Around it, gas swirls in a flat disk, so hot that it glows. That's the
> accretion disk."
> "Light that passes very close gets bent all the way around the hole, and
> piles up in a thin, bright circle: the photon ring."
> "The dark middle is the shadow: light that came too close, and fell in."

**a2 · Only two numbers**
Visual: two black holes side by side, one bigger, one spinning (arrow).
> "Scientists love black holes because they're surprisingly simple. To
> describe a cat, you'd need a long list: colour, size, weight, personality,
> favourite food."
> "A black hole needs just [two](+2) numbers: how heavy it is, and how fast it
> spins. Measure its picture, and you can learn both."

**a3 · Tiny in the sky**
Visual: the Earth, zoom out to the Moon, an orange on the Moon (labelled),
then the angle it spans as a thin wedge.
> "The black hole in the galaxy M87 is enormous: its shadow is bigger than
> our whole solar system. But it's fifty-five million light-years away."
> "Seen from Earth, it looks as small as an [orange](+2), sitting on the Moon."

**a4 · Why you need a giant telescope**
Visual: the resolution rule from the telescope film, λ ÷ D, as a card; a dish
growing until it's as wide as the Earth.
> "How fine a detail a telescope can see depends on two things: the
> wavelength of the light, and the width of its opening."
> "These black holes are best seen in radio light, about a millimetre long.
> To see an orange on the Moon at that wavelength, the opening has to be
> about as wide as the [Earth](+2)."

## Act 2: a telescope the size of the Earth

**b0 · Telescopes all over the world**
Visual: a globe, the Event Horizon Telescope's stations lighting up one by
one, lines between them.
> "Nobody can build a dish that big. So instead, astronomers point radio
> telescopes all over the world at the [same](+2) black hole, at the same
> moment: in Hawaii, Arizona, Mexico, Chile, Spain, France, Greenland and at
> the South Pole."
> "Together they act like pieces of one giant dish. This is the Event Horizon
> Telescope."

**b1 · Each pair hears one note**
Visual: two stations and the line between them; beside it the picture, and
the stripe pattern that pair measures. Shorter line: wide stripes; longer:
fine stripes.
> "But pieces of a dish don't take a picture. Each [pair](+2) of telescopes
> measures one thing: how strongly one stripe pattern is hidden in the
> picture."
> "A pair close together measures wide stripes, the coarse shape. A pair far
> apart measures fine stripes: the small details."
> "Think of the picture as a piece of music. Every pair of telescopes hears
> just [one](+2) note of it."

**b2 · The Earth turns**
Visual: the globe turns; each pair's note traces a curve in a "note map"
(the uv-plane), filling in over a night.
> "With eight sites, that's only a few notes. But the Earth turns, and as it
> does, each pair sees the black hole from a slightly different angle, and
> hears a slightly different note."
> "Over one night, the notes trace out these curves. Still, most of the music
> is missing."

**b3 · Guess that song**
Visual: the true ring, the few measured notes, and three quite different
pictures that all match those notes.
> "From just these notes, many different pictures would fit. It's like
> guessing a song from a handful of notes."
> "So the picture isn't measured directly. It has to be [inferred](+2): found by
> computer, as the picture that best explains the notes."

**b4 · From the telescopes to the computer**
Visual: a simple animated diagram: disks in planes, a correlator, a
calibration step, the image.
> "Each telescope records its signal onto hard drives, petabytes of them.
> The drives are flown to a supercomputer, which combines every pair."
> "Then the data are cleaned of the atmosphere's and the instruments' errors,
> and only then can the picture be made."

## Act 3: making the picture, honestly

**c0 · Not one picture, but many**
Visual: a grid of pictures that all fit the notes, then their average and
how much they disagree.
> "Older methods gave a single picture, and astronomers argued about which
> parts of it were real."
> "A better way is to find [all](+2) the pictures that fit the data, and how
> likely each one is. Where they agree, we can trust the picture; where they
> disagree, we know we're unsure."

**c1 · The price, and Julia**
Visual: two bars: a week on a thousand computers vs half an hour on one.
> "But that means trying out millions of pictures, and it used to take about
> a week on a thousand processors."
> "Written in Julia, the same kind of analysis, Comrade.jl, takes about half
> an hour on [one](+2), with forty times more detail in the model."

**c2 · Sharper still: a telescope in space**
Visual: the globe with a satellite orbiting far out; the note map extends
beyond the Earth's curves; the ring sharpens to its thin photon ring.
> "To see sharper, we need an even bigger telescope, bigger than the Earth.
> The Black Hole Explorer will put a radio dish in space."
> "Its notes reach much higher, fine enough to see the thin photon ring
> itself. And all of its data will be turned into pictures with Julia."

**c3 · Outro**
Visual: back to the first picture, now sharp.
> "A picture of a black hole isn't taken. It's [computed](+2): from a few notes,
> heard by telescopes all over the Earth."
> "Better software means better science, and sharper pictures of the edge of
> the universe."
