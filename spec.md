Implement a framework of an agentic engineering scaffold that can be used to independently develop an application or software project based on a specfile. 

I will suggest a basic framework in the following. Do a deep and thorough websearch to figure out 2026 best practices. 
Do not just take anything you find for granted. Scan what people claim is working over multiple sources. In particular rely on Anthropic documentation of various concepts. Criticize my setup figure out what needs improvements. Do a socratic analysis of your own suggestion and iterate until you are certain we have a setup that has no clear "better version". 

Basic Framework:

Every project gets implemented by a subset of available agents (the supervisor decides who to utilize). There exists an agents.env file that has fields like: frontend-repo, backend-repo that contains URLs and other project specific variables. 

Each feature shall be compressed into a single commit (one for frontend and one for backend). All relevant decisions should be tracked in a folder with the commit name and contain: task.md review.md (potentially multiple rounds) 
and a feedback.md (the feedback.md is human written and should be used to improve the agent pipeline.) 

1. Supervisor -- This agent reads the spec file and turns it into a list of TODOs. This agent is responsible for calling the relevant agents and supervising their tasks.
2. Backend Engineer - This agent gets the backend part of the TODO and produces production ready code.
3. Frontend Engineer - This agent gets the frontend part of the TODO and produces production ready code 
4. Frontend Designer - This agent conceptuallizes outstanding and fresh UI/UX. 
5. Test Engineer - This agent conceives of bulletproof testing suites for both unit and integration tests. 
6. Reviewer - Expert in code-review. Is responsible for security checks and general code quality and dedup. The overarching goal is to keep the codebase as lean as possible 
7. Agentic Resources - This agent is a meta agent that analyses the done tasks and identifies weaknesses in the pipeline. Does the reviewer always flag a certain problem? How can we make sure this does not occur in the next development cycle. Does the feedback of the human clarify how a certain agent misunderstood its task? How can we prevent this from happening again in the future? 
8. Tool Engineer - This agent develops custom tools for the other agents to use for a given project. 


Things to figure out / Design principles: 

- How to handle memory? Keep token usage in mind!
- Make sure we have a single source of truth to avoid drift.
- After each task clear the context. If it is sensible to keep a piece of information in mind, write it to memory of the supervisor. 
- How to communicate with the human? can the supervisor access telegram or whatsapp? 
- How to make sure that improvements to the agent body translate across projects? Should every project clone this repo alongside the frontend-backend repos? Something else? 
- Generally: how can we built feedback loops that turn this into a self improving machine
- VERY IMPORTANT: ALL THE .mds and agent specs etc have to be CONCISE! AVOID wordy examples. Tweak sentences to be short and precise so an agent knows what is up no matter in which project it operates. 

