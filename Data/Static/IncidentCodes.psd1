# Shelter House Data Pipeline - Incident Codes

@{
    #region FATAL
    F0S_001 = @{
        Stage = "Orchestration"
        Category = "Staging"
        Level = "Fatal"
        Message = "Fatal error in stage orchestration"
        Recommendation = "Check log files for details"
    }
    F0S_002 = @{
        Stage = "Orchestration"
        Category = "Staging"
        Level = "Fatal"
        Message = "Unable to stop stage and prepare context to continue"
        Recommendation = "Check log files for details"
    }
    #endregion FATAL


    #region Error
    # E0C_001 = @{
    #     Stage = "Orchestration"
    #     Category = "Configuration"
    #     Level = "Error"
    #     Message = "Unable to locate manifest directory"
    #     Recommendation = "Check configuration settings"
    # }
    E0S_001 = @{
        Stage = "Orchestration"
        Category = "Staging"
        Level = "Error"
        Message = "Unable to start stage"
        Recommendation = "Check logs for details"
    }
    #endregion Error


    #region Warning
    W0C_001 = @{
        Stage = "Orchestration"
        Category = "Configuration"
        Level = "Warning"
        Message = "Project_Details.csv not found in the provided path"
    }
    W0C_002 = @{
        Stage = "Orchestration"
        Category = "Configuration"
        Level = "Warning"
        Message = "Unable to load HUD_Schema into context"
    }
    W0C_003 = @{
        Stage = "Orchestration"
        Category = "Configuration"
        Level = "Warning"
        Message = "Unable to load Project_Details into context"
    }
    W0F_001 = @{
        Stage = "Orchestration"
        Category = "File I/O"
        Level = "Warning"
        Message = "Unable to load manifest from provided path"
    }
    W0S_001 = @{
        Stage = "Orchestration"
        Category = "Staging"
        Level = "Warning"
        Message = "Pipeline did not close out successfully"
    }
    W0S_002 = @{
        Stage = "Orchestration"
        Category = "Staging"
        Level = "Warning"
        Message = "Stage sequence does not match expectation"
        Recommendation = "Check configuration settings"
    }
    W0S_003 = @{
        Stage = "Orchestration"
        Category = "Staging"
        Level = "Warning"
        Message = "Skipping stage per pipeline configuration"
    }
    W0S_004 = @{
        Stage = "Orchestration"
        Category = "Staging"
        Level = "Warning"
        Message = "Unable to build manifest object"
    }
    W0S_005 = @{
        Stage = "Orchestration"
        Category = "Staging"
        Level = "Warning"
        Message = "Unable to retrieve manifest object"
    }
    W0S_006 = @{
        Stage = "Orchestration"
        Category = "Staging"
        Level = "Warning"
        Message = "Unable to save manifest to disk"
    }
    #endregion Warning


    #region Info
    I0S_001 = @{
        Stage = "Orchestration"
        Category = "Staging"
        Level = "Info"
        Message = "Pipeline successfully initiated"
    }
    I0S_002 = @{
        Stage = "Orchestration"
        Category = "Staging"
        Level = "Info"
        Message = "Stage input data loaded successfully"
    }
    I0S_003 = @{
        Stage = "Orchestration"
        Category = "Staging"
        Level = "Info"
        Message = "Attempting to load manifest data from backup"
    }
    I0S_004 = @{
        Stage = "Orchestration"
        Category = "Staging"
        Level = "Info"
        Message = "Starting Stage"
    }
    #endregion Info


    #region Debug
    D0F_001 = @{
        Stage = "Orchestration"
        Category = "File I/O"
        Level = "Debug"
        Message = "Manifest save path established"
    }
    #endregion Debug
}