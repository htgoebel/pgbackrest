/***********************************************************************************************************************************
Test Types
***********************************************************************************************************************************/
void
testRun()
{
    // -----------------------------------------------------------------------------------------------------------------------------
    if (testBegin("test int size"))
    {
        // Ensure that int is at least 4 bytes
        assert(sizeof(int) >= 4);
    }

    // -----------------------------------------------------------------------------------------------------------------------------
    if (testBegin("test boolean values"))
    {
        // Ensure false and true are defined
        assert(true);
        assert(!false);
    }
}
