@{
    # PSScriptAnalyzer configuration for NetMonTool.
    #
    # We run the default rule set at Error + Warning severity. A few rules
    # are excluded because they conflict with the deliberate design of this
    # tool (single-file portability, an intentional infinite monitoring
    # loop, and Write-Host being the correct choice for a console dashboard).

    Severity = @('Error', 'Warning')

    ExcludeRules = @(
        # The dashboard IS a console UI. Write-Host is the correct, intended
        # tool for drawing colored tiles to the screen.
        'PSAvoidUsingWriteHost',

        # The main monitoring loop is an intentional `while ($true)`; it runs
        # until the operator presses CTRL + C. This is by design.
        'PSAvoidUsingEmptyCatchBlock'  # catches are intentional "never crash
                                       # the dashboard" guards, documented inline
    )

    # Rules we explicitly WANT enforced are left on by default. Non-approved
    # verb warnings (Draw-/Load-/Save-) are intentionally NOT excluded so the
    # analyzer keeps surfacing them until the planned rename pass lands.
}
