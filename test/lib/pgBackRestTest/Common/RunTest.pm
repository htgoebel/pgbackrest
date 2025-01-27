####################################################################################################################################
# RunTest.pm - All tests are inherited from this object
####################################################################################################################################
package pgBackRestTest::Common::RunTest;

####################################################################################################################################
# Perl includes
####################################################################################################################################
use strict;
use warnings FATAL => qw(all);
use Carp qw(confess);
use English '-no_match_vars';

use Exporter qw(import);
    our @EXPORT = qw();
use File::Basename qw(dirname);

use pgBackRestDoc::Common::Exception;
use pgBackRestDoc::Common::Log;
use pgBackRestDoc::Common::String;
use pgBackRestDoc::ProjectInfo;

use pgBackRestTest::Common::BuildTest;
use pgBackRestTest::Common::DefineTest;
use pgBackRestTest::Common::ExecuteTest;
use pgBackRestTest::Common::Storage;
use pgBackRestTest::Common::StoragePosix;
use pgBackRestTest::Common::VmTest;
use pgBackRestTest::Common::Wait;

####################################################################################################################################
# Constant to use when bogus data is required
####################################################################################################################################
use constant BOGUS =>                                               'bogus';
    push @EXPORT, qw(BOGUS);

####################################################################################################################################
# The current test run that is executing. Only a single run should ever occur in a process to prevent various cleanup issues from
# affecting the next run. Of course multiple subtests can be executed in a single run.
####################################################################################################################################
my $oTestRun;
my $oStorage;

####################################################################################################################################
# new
####################################################################################################################################
sub new
{
    my $class = shift;          # Class name

    # Create the class hash
    my $self = {};
    bless $self, $class;

    # Assign function parameters, defaults, and log debug info
    my ($strOperation) = logDebugParam(__PACKAGE__ . '->new');

    # Initialize run counter
    $self->{iRun} = 0;

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'self', value => $self, trace => true}
    );
}

####################################################################################################################################
# initModule
#
# Empty init sub in case the ancestor class does not declare one.
####################################################################################################################################
sub initModule {}

####################################################################################################################################
# initTest
#
# Empty init sub in case the ancestor class does not declare one.
####################################################################################################################################
sub initTest {}

####################################################################################################################################
# cleanTest
#
# Delete all files in test directory.
####################################################################################################################################
sub cleanTest
{
    my $self = shift;

    executeTest('rm -rf ' . $self->testPath() . '/*');
}

####################################################################################################################################
# cleanModule
#
# Empty final sub in case the ancestor class does not declare one.
####################################################################################################################################
sub cleanModule {}

####################################################################################################################################
# process
####################################################################################################################################
sub process
{
    my $self = shift;

    # Assign function parameters, defaults, and log debug info
    (
        my $strOperation,
        $self->{strVm},
        $self->{iVmId},
        $self->{strBasePath},
        $self->{strTestPath},
        $self->{strBackRestExe},
        $self->{strBackRestExeHelper},
        $self->{strPgBinPath},
        $self->{strPgVersion},
        $self->{strModule},
        $self->{strModuleTest},
        $self->{iyModuleTestRun},
        $self->{bOutput},
        $self->{bDryRun},
        $self->{bCleanup},
        $self->{strLogLevelTestFile},
        $self->{strPgUser},
        $self->{strGroup},
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->process', \@_,
            {name => 'strVm'},
            {name => 'iVmId'},
            {name => 'strBasePath'},
            {name => 'strTestPath'},
            {name => 'strBackRestExe'},
            {name => 'strBackRestExeHelper'},
            {name => 'strPgBinPath', required => false},
            {name => 'strPgVersion', required => false},
            {name => 'strModule'},
            {name => 'strModuleTest'},
            {name => 'iModuleTestRun', required => false},
            {name => 'bOutput'},
            {name => 'bDryRun'},
            {name => 'bCleanup'},
            {name => 'strLogLevelTestFile'},
            {name => 'strPgUser'},
            {name => 'strGroup'},
        );

    # Init will only be run on first test, clean/init on subsequent tests
    $self->{bFirstTest} = true;

    # Initialize test storage
    $oStorage = new pgBackRestTest::Common::Storage(
        $self->testPath(), new pgBackRestTest::Common::StoragePosix({bFileSync => false, bPathSync => false}));

    # Init, run, and clean the test(s)
    $self->initModule();
    $self->run();
    $self->cleanModule();

    # Make sure the correct number of tests ran
    my $hModuleTest = testDefModuleTest($self->{strModule}, $self->{strModuleTest});

    if ($hModuleTest->{&TESTDEF_TOTAL} != $self->runCurrent())
    {
        confess &log(ASSERT, "expected $hModuleTest->{&TESTDEF_TOTAL} tests to run but $self->{iRun} ran");
    }

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'self', value => $self, trace => true}
    );
}

####################################################################################################################################
# begin
####################################################################################################################################
sub begin
{
    my $self = shift;

    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $strDescription,
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->begin', \@_,
            {name => 'strDescription'},
        );

    # Increment the run counter;
    $self->{iRun}++;

    # Return if this test should not be run
    if (@{$self->{iyModuleTestRun}} != 0 && !grep(/^$self->{iRun}$/i, @{$self->{iyModuleTestRun}}))
    {
        return false;
    }

    # Output information about test to run
    &log(INFO, 'run ' . sprintf('%03d', $self->runCurrent()) . ' - ' . $strDescription);

    if ($self->isDryRun())
    {
        return false;
    }

    if (!$self->{bFirstTest})
    {
        $self->cleanTest();
    }

    $self->initTest();
    $self->{bFirstTest} = false;

    return true;
}

####################################################################################################################################
# testResult
####################################################################################################################################
sub testResult
{
    my $self = shift;

    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $fnSub,
        $strExpected,
        $strDescription,
        $iWaitSeconds,
    ) =
        logDebugParam
        (
            __PACKAGE__ . '::testResult', \@_,
            {name => 'fnSub', trace => true},
            {name => 'strExpected', required => false, trace => true},
            {name => 'strDescription', trace => true},
            {name => 'iWaitSeconds', optional => true, default => 0, trace => true},
        );

    &log(INFO, '    ' . $strDescription);
    my $strActual;
    my $bWarnValid = true;

    my $oWait = waitInit($iWaitSeconds);
    my $bDone = false;

    # Clear the cache for this test
    logFileCacheClear();

    my @stryResult;

    do
    {
        eval
        {
            @stryResult = ref($fnSub) eq 'CODE' ? $fnSub->() : $fnSub;

            if (@stryResult <= 1)
            {
                $strActual = ${logDebugBuild($stryResult[0])};
            }
            else
            {
                $strActual = ${logDebugBuild(\@stryResult)};
            }

            return true;
        }
        or do
        {
            if (!isException(\$EVAL_ERROR))
            {
                confess "unexpected standard Perl exception" . (defined($EVAL_ERROR) ? ": ${EVAL_ERROR}" : '');
            }

            confess &logException($EVAL_ERROR);
        };

        if ($strActual ne (defined($strExpected) ? $strExpected : "[undef]"))
        {
            if (!waitMore($oWait))
            {
                confess
                    "expected:\n" . (defined($strExpected) ? "\"${strExpected}\"" : '[undef]') .
                    "\nbut actual was:\n" . (defined($strActual) ? "\"${strActual}\"" : '[undef]');
            }
        }
        else
        {
            $bDone = true;
        }
    } while (!$bDone);

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'result', value => \@stryResult, trace => true}
    );
}

####################################################################################################################################
# testRunName
#
# Create module/test names by upper-casing the first letter and then inserting capitals after each -.
####################################################################################################################################
sub testRunName
{
    my $strName = shift;
    my $bInitCapFirst = shift;

    $bInitCapFirst = defined($bInitCapFirst) ? $bInitCapFirst : true;
    my $bFirst = true;

    my @stryName = split('\-', $strName);
    $strName = undef;

    foreach my $strPart (@stryName)
    {
        $strName .= ($bFirst && $bInitCapFirst) || !$bFirst ? ucfirst($strPart) : $strPart;
        $bFirst = false;
    }

    return $strName;
}

push @EXPORT, qw(testRunName);

####################################################################################################################################
# testRun
####################################################################################################################################
sub testRun
{
    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $strModule,
        $strModuleTest,
    ) =
        logDebugParam
        (
            __PACKAGE__ . '::testRun', \@_,
            {name => 'strModule', trace => true},
            {name => 'strModuleTest', trace => true},
        );

    # Error if the test run is already defined - only one run per process is allowed
    if (defined($oTestRun))
    {
        confess &log(ASSERT, 'a test run has already been created in this process');
    }

    my $strModuleName =
        'pgBackRestTest::Module::' . testRunName($strModule) . '::' . testRunName($strModule) . testRunName($strModuleTest) .
        'Test';

    $oTestRun = eval("require ${strModuleName}; ${strModuleName}->import(); return new ${strModuleName}();")
        or do {confess $EVAL_ERROR};

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'oRun', value => $oTestRun, trace => true}
    );
}

push @EXPORT, qw(testRun);

####################################################################################################################################
# testRunGet
####################################################################################################################################
sub testRunGet
{
    return $oTestRun;
}

push @EXPORT, qw(testRunGet);

####################################################################################################################################
# storageTest - get the storage for the current test
####################################################################################################################################
sub storageTest
{
    return $oStorage;
}

push(@EXPORT, qw(storageTest));

####################################################################################################################################
# Getters
####################################################################################################################################
sub archBits {return vmArchBits(shift->{strVm})}
sub backrestExe {return shift->{strBackRestExe}}
sub backrestExeHelper {return shift->{strBackRestExeHelper}}
sub basePath {return shift->{strBasePath}}
sub dataPath {return shift->basePath() . '/test/data'}
sub doCleanup {return shift->{bCleanup}}
sub logLevelTestFile {return shift->{strLogLevelTestFile}}
sub group {return shift->{strGroup}}
sub isDryRun {return shift->{bDryRun}}
sub module {return shift->{strModule}}
sub moduleTest {return shift->{strModuleTest}}
sub pgBinPath {return shift->{strPgBinPath}}
sub pgUser {return shift->{strPgUser}}
sub pgVersion {return shift->{strPgVersion}}
sub runCurrent {return shift->{iRun}}
sub stanza {return 'db'}
sub testPath {return shift->{strTestPath}}
sub vm {return shift->{strVm}}
sub vmId {return shift->{iVmId}}

1;
