/// English UI strings — the reference table.
///
/// Every other language file in this folder must carry exactly these keys
/// (`strings_test.dart` fails the build otherwise). Missing keys fall back
/// to this table at lookup time, so a half-finished language never blanks
/// the screen.
///
/// `{n}` inside a value is a placeholder substituted by the caller — do not
/// translate or drop it.
library;

const Map<String, String> kEn = {
  'appTitle': 'Peep Science',
  'homeTagline': 'Build · Test · Discover',
  'world1': 'Bedroom',
  'world2': 'Backyard',
  'world3': 'Toy Factory',
  'world4': 'Space',
  'world5': 'Peep Lab',
  'stageN': 'Stage {n}',
  'clear': 'CLEAR!',
  'next': 'Next',
  'retry': 'Retry',
  'play': 'Play',
  'settings': 'Settings',
  'sound': 'Sound',
  'language': 'Language',
  'langSystem': 'System',
  'goalBasket': 'Ball into the basket!',
  'goalButton': 'Press the button!',
  'goalBalloons': 'Pop all balloons!',
  'goalDominoes': 'Topple all dominoes!',
  'dragHint': 'Drag a part in, turn the yellow handle, then press play.',
  'dragHintNoTurn': 'Drag a part in, then press play.',
  'clearMessage': 'Your contraption came to life!',
  'scienceNote': 'OBSERVE',
  'factBasket': 'Slopes and rebounds change the path of a moving ball.',
  'factButton': 'A force can move an object or press it down.',
  'factBalloons': 'Light balloons move a lot when air pushes them.',
  'factDominoes': 'Motion can transfer from one object to the next.',
  'home': 'Home',
  'playStage': 'Play stage',
  'predictionQuestion': 'Which ball will work better?',
  'predictionHint': 'Choose first, then run the experiment!',
  'predictionCorrect': 'Prediction matched the result!',
  'predictionWrong': 'A surprise result — try the other material!',
  'chainReaction': 'CHAIN REACTION',
  'challengeTitle': 'STAR CHALLENGE',
  'partLimit': 'Parts allowed',
  'starsEarned': 'Stars earned',
  'tutorialHelp': 'Experiment guide',
  'tutorialTitle': "Professor Peep's Lab Notes",
  'tutorialSubtitle': "Four tiny steps and you're a scientist too!",
  'tutorialGoalTitle': '1. Check the mission card',
  'tutorialGoalBody':
      'Each stage has a different goal. Tap the mission card to make the basket, button, balloon, or domino bounce.',
  'tutorialDragTitle': '2. Drag in a part',
  'tutorialDragBody':
      'Pull a part up from the tray and drop it in an empty space. A yellow guide means the spot is ready.',
  'tutorialRotateTitle': '3. Turn the yellow handle',
  'tutorialRotateBody':
      'Tap the plank you placed, then turn its yellow handle to build a path for the ball.',
  'tutorialRunTitle': '4. Run and observe',
  'tutorialRunBody':
      'Press the green play button. A miss is useful too: your parts stay put, so adjust them and test again!',
  'tutorialSkip': 'Skip for now',
  'tutorialBack': 'Back',
  'tutorialNext': 'Next',
  'tutorialStart': 'Start experiment',
};
