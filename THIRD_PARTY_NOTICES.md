# Attribution and reuse notes

The signal-processing implementation in this repository is newly written Dart. No upstream Python source, WAV recordings or images are redistributed here.

Scientific and exploratory references:

- Joao Nuno Carvalho, *Partial implementation of the ApneaAPP paper — FMCW sonar*, commit `3677815c2e955a554aaa6e2e1e23c8bd4b5f04fd`: https://github.com/joaocarvalhoopen/Partial_implementation_of_the_ApneaAPP_paper___FMCW_sonar . Its README declares “MIT Open Source license”; the inspected tree lacks the full license text and file-level notices. Coverage/ownership of the sample WAV and images remains unresolved. Preserve the author's notice and obtain/record the applicable permission text before copying code or redistributing those assets. The current Dart implementation does neither.
- Rajalakshmi Nandakumar, Shyamnath Gollakota and Nathaniel Watson, *Contactless Sleep Apnea Detection on Smartphones*: https://apnea.cs.washington.edu/apneaapp.pdf . The researchers' Android implementation and clinical findings are not validation of this MVP. The paper is referenced, not bundled.
- Sidhant Gupta, Daniel Morris, Shwetak Patel and Desney Tan, *SoundWave: Using the Doppler Effect to Sense Gestures*: https://www.microsoft.com/en-us/research/wp-content/uploads/2012/05/guptasoundwavechi2012.pdf . This is background for acoustic Doppler sensing, not a claim of replicated performance.

Flutter, Dart, SDK packages and transitive dependency versions are recorded in `pubspec.lock`; their respective upstream licenses govern them. Flutter's generated web `assets/NOTICES` contains dependency notices and its application license registry is available through the app's About dialog. No patent clearance is asserted. This notice does not invent or change the license of the new project code.
