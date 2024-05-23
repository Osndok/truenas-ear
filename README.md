
truenas-ear

"ear" -> "encryption at rest"

This is a small utility intended to make encryption-at-rest easier with truenas.

It works by having a setuid binary that calls specific zfs commands on behalf
of non-root users to:
* test if a dataset is unlocked
* provide a decryption key
* mount a dataset
* mount nested datasets (with inherited encryption)
* start services related to that unlocked dataset
* run post-mount scripts related to the unlocked dataset

