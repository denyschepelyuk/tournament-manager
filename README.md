# tournament-manager
Processes different teams scores, calculates them and generates overall summary as well as each teams characteristics

Repository contains tournament.sh executable script

### Usage:
+ Should be run from inside the repository you want to process
+ Accepts arguments -o <output_dir> and -t <index_title>
  + Is able to handle both formats: -o <output_dir> and -o<output_dir>


Repository contains two input examples directories:
- demo
  - is basic example with only logs
- hogwarts
  - is more advanced example with tasks/config.rc and tasks/<module_name>/meta.rc configuration files that can describe such configuration details as each custom module name and index.md file title


Input tasks directory has following format:

```
tasks/
├── m01
│   ├── alpha.log.gz
│   └── bravo.log.gz
└── m02
    ├── alpha.log.gz
    ├── bravo.log.gz
    └── charlie.log.gz
```
where m01, m02 are module names and m01/alpha.log.gz, m01/beta.log.gz, m02/alpha.log.gz, ... are team log files that describe their performance in each tournament module.


tournament.sh will generate such a file construction:

index.md total teams scores:

```
# My tournament

 1. bravo (5 points)
 2. alpha (3 points)
 3. charlie (1 points)
```
And for each team a special page like this:

```
# Team alpha

+--------------------+--------+--------+--------------------------------------+
| Task               | Passed | Failed | Links                                |
+--------------------+--------+--------+--------------------------------------+
| m01                |      1 |      2 | [Complete log](m01.log).             |
| m02                |      2 |      0 | [Complete log](m02.log).             |
+--------------------+--------+--------+--------------------------------------+
```
The output directory would then contain the following files:

```
out/
├── index.md
├── team-alpha
│   ├── index.md
│   ├── m01.log
│   └── m02.log
├── team-bravo
│   ├── index.md
│   ├── m01.log
│   └── m02.log
└── team-charlie
    ├── index.md
    ├── m01.log
    └── m02.log
```
