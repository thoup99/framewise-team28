
package Editor_Application is
   --  Initialize and Shutdown also let regression tests exercise the real UI
   --  without entering the interactive event loop. Call each once per process.
   procedure Initialize;

   procedure Run;

   procedure Shutdown;
end Editor_Application;
