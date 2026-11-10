--  The session: the single entry point for every front end.
--
--     Execute (S, "place c1 v1 intro 12.0 18.5 4.0", Response)
--
--  State = a Sequence + render settings + the history of modeling
--  commands. Undo pops the history and replays from empty. Save writes
--  the history; load replays a file. The .fw document IS the history.
--
--  No heap needed: a Sequence is bounded and lives inside the Session.
--  Export spawns ffmpeg with the plan; plan only prints it. Proxy spawns
--  ffmpeg once per source to make the intra-only file the editor reads.

with GNAT.OS_Lib;
with Bedrock.Responses;
with Framewise.Commands; use Framewise.Commands;
with Framewise.Plan;
with Framewise.Timeline;

package Framewise.Session is

   Max_History : constant := 4096;

   type Session is limited private;

   Max_Response : constant := 16_384;

   --  The GAP line protocol's reply, from bedrock: "ok", "ok <info>",
   --  or "err <reason>". Same type in forge and yarlib's console.
   package Responses is new Bedrock.Responses (Max_Response);
   subtype Response is Responses.Response;
   function Image (R : Response) return String renames Responses.Image;

   function Quote_Path (File : String) return String renames Commands.Quote_Path;

   type Export_Job is limited private;
   function Export_Running (Job : Export_Job) return Boolean;
   function Export_Percent (Job : Export_Job) return Natural;
   --  Monotonic within a job; 100 is reserved for successful process completion.
   procedure Start_Export
     (S : Session; Output : String; Job : in out Export_Job; R : out Response;
      Wait_In_Background : Boolean := False);
   procedure Poll_Export (Job : in out Export_Job; R : out Response; Done : out Boolean);
   --  The plan is captured at launch. Poll never changes the document and
   --  returns FFmpeg diagnostics when the child finishes. One active job per editor.
   --  Windows uses a background blocking wait: GNAT's nonblocking wait is not
   --  supported there. True forces that fallback on other runtimes as well;
   --  Windows always uses it, regardless of this option.
   function Export_Output (Line : String) return String;
   --  Recognize a valid console export without duplicating command parsing in UI.

   procedure Execute (S : in out Session; Line : String; R : out Response);

   ---------------------------------------------------------------------
   --  Read-back for front ends
   ---------------------------------------------------------------------

   subtype Media_Kind is Timeline.Media_Kind;
   subtype Sequence_View is Timeline.Sequence;

   function Sequence_Of (S : Session) return Sequence_View;
   --  A copy; the GUI draws the timeline from it. Bounded, so cheap
   --  enough per Execute.

   function Settings_Of (S : Session) return Plan.Settings;

   function Image_Time (T : Framewise.Time) return String
      renames Framewise.Commands.Image_Time;

   function History_Length (S : Session) return Natural;
   function History_Line (S : Session; I : Positive) return String
     with Pre => I <= History_Length (S);

private

   protected type Export_Completion is
      procedure Finish (Success : Boolean);
      function Succeeded return Boolean;
   private
      Ok : Boolean := False;
   end Export_Completion;
   type Export_Completion_Access is access Export_Completion;

   task type Export_Waiter (Result : Export_Completion_Access) is
      entry Await (PID : GNAT.OS_Lib.Process_Id);
   end Export_Waiter;
   type Export_Waiter_Access is access Export_Waiter;

   type Export_Job is limited record
      PID : GNAT.OS_Lib.Process_Id := GNAT.OS_Lib.Invalid_Pid;
      Log_File : GNAT.OS_Lib.String_Access := null;
      Output : Path;
      Progress_File : GNAT.OS_Lib.String_Access := null;
      Total_Time : Time := 0;
      Percent : Natural range 0 .. 100 := 0;
      Progress_Offset : Long_Long_Integer := 0;
      Progress_Line : String (1 .. 128) := [others => ' '];
      Progress_Length : Natural range 0 .. 128 := 0;
      Progress_Overflow : Boolean := False;
      Completion : Export_Completion_Access := null;
      Waiter : Export_Waiter_Access := null;
   end record;

   type History_Array is array (1 .. Max_History) of Command;

   type Session is limited record
      Seq     : Timeline.Sequence;
      Cfg     : Plan.Settings := Plan.Default_Settings;
      History : History_Array;
      Count   : Natural := 0;
   end record;

end Framewise.Session;
