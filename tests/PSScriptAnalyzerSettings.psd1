# Used for tests/ only. Pester assigns variables in BeforeAll that are read in It
# blocks; PSScriptAnalyzer cannot see across those script blocks and reports them
# as unused (a documented false positive). scripts/ is analyzed with default rules.
@{
    ExcludeRules = @('PSUseDeclaredVarsMoreThanAssignments')
}
