"""
Which models the forge builds against.

One place, because the model id appeared in five scripts and a mismatch
between the one that builds the centroids and the one that embeds a query is
silent: both produce unit vectors, the cosines look plausible, and the
classifications are simply wrong.
"""

# ESM-2 t12-35M, 33.5M parameters, 480 dimensions.
#
# Chosen over t6-8M on measurement, not size. Against the same 2,500 real
# UniProt proteins and the same 220 multi-domain proteins:
#
#                        t6-8M    t12-35M
#   real top-1           0.430    0.471
#   real top-5           0.493    0.540
#   multi-domain recall  0.358    0.478
#   multi-domain prec.   0.76     0.84
#
# The multi-domain numbers are the ones that mattered: the architecture track
# is what the Grammarian consumes, and it finds a third more domains at higher
# precision. The cost is 5.2x on the Neural Engine, 6.0 ms to 31.3 ms per
# window, which takes a 536-residue protein from 247 ms to about 1.3 s.
PROTEIN_MODEL_ID = "facebook/esm2_t12_35M_UR50D"

# MiniLM is unchanged: the Field Guide's semantic search was never the weak
# part, and the text model is a third of the bundle already.
TEXT_MODEL_ID = "sentence-transformers/all-MiniLM-L6-v2"
