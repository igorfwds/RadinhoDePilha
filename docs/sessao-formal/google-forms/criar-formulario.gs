/**
 * Builds the post-use questionnaire for the Radinho de Pilha evaluation as a Google Form.
 *
 * How to use: sign in to the PERSONAL Google account that should own the research data, open
 * script.google.com, create a project, paste this file, choose `createPostUseForm` in the
 * function list and run it once. Google asks for permission to manage forms. The links to
 * answer and to edit the form appear in the execution log.
 *
 * Decisions that shape the form:
 * - Anonymous: no e-mail collection, no sign-in, no name. Age, city and favourite club are not
 *   asked either, because with two to five respondents they could identify someone.
 * - Short on purpose: 33 questions, 25 required, 6 open. Every extra open question costs a
 *   screen-reader user minutes, and the closing questions already catch what was left out.
 * - Plain controls only (multiple choice, text, 1 to 5 scale). Grids read badly with a screen
 *   reader, so every task is its own question.
 * - One required question says which match the answers are about, as free text, because a date
 *   picker is awkward with VoiceOver and the respondent may remember only the teams.
 * - Consent is a required checkbox, so the form cannot be sent without it.
 *
 * All text shown to respondents is in Brazilian Portuguese on purpose.
 */

const FORM_TITLE = 'Radinho de Pilha: como foi usar o aplicativo?';

const INTRO_TEXT = [
  'Este formulário faz parte de uma pesquisa de Trabalho de Conclusão de Curso da CESAR School sobre um aplicativo de iPhone que narra partidas de futebol por voz, o Radinho de Pilha.',
  '',
  'Pesquisador: Igor Felipe Wanderley da Silva. Orientador: Prof. Me. Marcelo Lima Arcoverde.',
  '',
  'Leva de 10 a 20 minutos, conforme quanto você queira escrever. Não existe resposta certa ou errada: quem está sendo avaliado é o aplicativo, não você. Se não lembrar de algo, pode pular as perguntas que não forem obrigatórias.',
  '',
  'O formulário é anônimo. Não pedimos nome, e-mail nem telefone, e ele não registra quem respondeu. Por isso, depois de enviar, não será possível apagar uma resposta específica, porque não há como saber qual é a sua. Por favor, não escreva seu nome nem dados que identifiquem você nas respostas escritas.',
  '',
  'Participar é voluntário. Você pode parar a qualquer momento, fechando a página: só as respostas enviadas ficam registradas. As respostas ficam guardadas no Google Forms, na conta do pesquisador, e serão usadas somente nesta pesquisa, de acordo com a Lei Geral de Proteção de Dados (Lei nº 13.709, de 2018).'
].join('\n');

const CONFIRMATION_TEXT = 'Obrigado por participar! Suas respostas foram enviadas.';

const TASK_ANSWERS = ['Consegui sozinho(a)', 'Consegui com dificuldade', 'Não consegui', 'Não usei'];

function createPostUseForm() {
  const form = FormApp.create(FORM_TITLE);

  form.setDescription(INTRO_TEXT);
  form.setCollectEmail(false);
  form.setLimitOneResponsePerUser(false);
  form.setAllowResponseEdits(false);
  form.setShowLinkToRespondAgain(false);
  form.setProgressBar(true);
  form.setPublishingSummary(false);
  form.setConfirmationMessage(CONFIRMATION_TEXT);

  // Only meaningful for Workspace accounts; harmless to attempt on a personal one.
  try {
    form.setRequireLogin(false);
  } catch (error) {
    Logger.log('setRequireLogin skipped: ' + error);
  }

  addConsent_(form);
  addMatchAndUse_(form);
  addAboutYou_(form);
  addTasks_(form);
  addComprehension_(form);
  addInformationAndDelay_(form);
  addSignals_(form);
  addVoice_(form);
  addConnection_(form);
  addOverall_(form);
  addClosing_(form);

  // Newer Google Forms keep a draft state until the form is published.
  if (typeof form.setPublished === 'function') {
    form.setPublished(true);
  }

  Logger.log('Link para responder: ' + form.getPublishedUrl());
  Logger.log('Link para editar: ' + form.getEditUrl());
}

// MARK: - Sections

/**
 * Consent is a single required checkbox: the form cannot be sent without it, and someone who does
 * not agree simply leaves, which records nothing. An earlier version sent "Não concordo" to the
 * end of the form through page navigation, and Google rejected it with "Dados inválidos ao
 * atualizar o formulário".
 */
function addConsent_(form) {
  const consent = form.addCheckboxItem();
  consent.setTitle('Consentimento');
  consent.setHelpText('Para responder, leia as informações acima e marque a caixa.');
  consent.setChoiceValues(['Li as informações acima e concordo em participar']);
  consent.setRequired(true);
}

function addMatchAndUse_(form) {
  addSection_(form, 'Sobre o jogo e o uso', 'Responda sobre o jogo em que você usou o aplicativo. Se usou em mais de um, escolha o que lembra melhor.');

  const match = form.addTextItem();
  match.setTitle('Qual jogo você acompanhou com o aplicativo?');
  match.setHelpText('Escreva os dois times, a data, ou os dois. Exemplo: Náutico x Novorizontino, 08/10.');
  match.setRequired(true);

  addChoice_(form, 'Onde você estava?', [
    'No estádio',
    'Em casa, com a TV ligada',
    'Em casa, só com o aplicativo'
  ], { required: true, other: true });

  addChoice_(form, 'Quanto tempo você usou o aplicativo nesse jogo?', [
    'Menos de 15 minutos',
    'De 15 a 45 minutos',
    'De 45 a 90 minutos',
    'O jogo todo'
  ], { required: true });

  addChoice_(form, 'Você estava usando o VoiceOver, o leitor de tela do iPhone, enquanto usava o aplicativo?', [
    'Sim',
    'Não'
  ], { required: true });
}

function addAboutYou_(form) {
  addSection_(form, 'Sobre você', 'Estas duas perguntas são opcionais e servem só para entender o conjunto das respostas. Não pedimos idade, cidade nem nome.');

  addChoice_(form, 'Como você descreveria sua condição visual?', [
    'Cegueira',
    'Baixa visão'
  ], { other: true });

  addChoice_(form, 'Com que frequência você usa o VoiceOver no dia a dia?', [
    'Todos os dias',
    'Algumas vezes por semana',
    'Raramente',
    'Não uso'
  ], {});
}

function addTasks_(form) {
  addSection_(form, 'O que você conseguiu fazer', 'Pense na primeira vez que usou o aplicativo. Para cada coisa abaixo, diga como foi.');

  const tasks = [
    'Fazer o aplicativo começar a narrar o jogo.',
    'Saber o placar e ouvir os lances mais recentes ou o resumo do jogo.',
    'Ouvir um lance de novo.',
    'Mudar os ajustes: a velocidade da voz, a voz, o estilo do narrador, e ligar ou desligar os sons e as vibrações.',
    'Entender os sons e as vibrações que avisam cada lance.'
  ];

  tasks.forEach(function (task) {
    addChoice_(form, task, TASK_ANSWERS, { required: true });
  });
}

function addComprehension_(form) {
  addSection_(form, 'O que você entendeu do jogo', 'Responda de memória, sem consultar nada. Se não lembrar, pode pular.');

  addText_(form, 'Quanto ficou o jogo no fim, ou na última vez que você ouviu?', false);
  addParagraph_(form, 'Quem fez os gols? Houve cartões? Para quem?', false);

  addChoice_(form, 'Alguma vez você ficou sabendo de um lance por outro meio, como a TV, a torcida ou alguém ao seu lado, antes de o aplicativo contar?', [
    'Nunca',
    'Poucas vezes',
    'Muitas vezes',
    'Quase sempre'
  ], { required: true });
}

function addInformationAndDelay_(form) {
  addSection_(form, 'Informações e atraso');

  const missing = form.addCheckboxItem();
  missing.setTitle('De que tipo de informação você sentiu falta?');
  missing.setHelpText('Marque quantas opções quiser.');
  missing.setChoiceValues([
    'Quem cometeu a falta',
    'Quem sofreu a falta',
    'Jogador caído ou machucado',
    'Escanteios',
    'Impedimentos',
    'Pênaltis',
    'Substituições',
    'Cartões',
    'Não senti falta de nada'
  ]);
  missing.showOtherOption(true);
  missing.setRequired(false);

  addScale_(form, 'O atraso do aplicativo atrapalhou?', 'Não atrapalhou', 'Atrapalhou muito', true);

  addChoice_(form, 'Quando um jogador ficou caído, o aplicativo ajudou a saber quem era?', [
    'Sim, sempre',
    'Às vezes',
    'Não ajudou',
    'Isso não aconteceu enquanto usei'
  ], { required: true });
}

function addSignals_(form) {
  addSection_(form, 'Sons e vibrações', 'Antes de cada lance, o aplicativo toca um som e faz uma vibração.');

  addChoice_(form, 'Você conseguiu perceber que tipo de lance era só pelos sons e pelas vibrações?', [
    'Sim, quase sempre',
    'Alguns eu conseguia',
    'Não consegui',
    'Desliguei os sons e as vibrações'
  ], { required: true });

  addChoice_(form, 'Pelos sons e pelas vibrações, você conseguiu saber se o lance era do seu time ou do adversário?', [
    'Sim',
    'Às vezes',
    'Não',
    'Não tenho time'
  ], { required: true });

  addChoice_(form, 'Os sons e as vibrações atrapalharam em algum momento?', [
    'Não',
    'Poucas vezes',
    'Muitas vezes'
  ], { required: true });
}

function addVoice_(form) {
  addSection_(form, 'Voz e narração');

  addChoice_(form, 'Qual estilo de narrador você usou?', [
    'Clássico',
    'Torcedor',
    'Analítico',
    'Não mudei o estilo',
    'Não lembro'
  ], { required: true });

  addChoice_(form, 'A velocidade da voz era:', [
    'Muito lenta',
    'Boa',
    'Muito rápida'
  ], { required: true });

  addChoice_(form, 'Você acha que essa voz cansaria em um jogo inteiro?', [
    'Sim',
    'Talvez',
    'Não'
  ], { required: true });
}

function addConnection_(form) {
  addSection_(form, 'Conexão com a internet');

  addChoice_(form, 'Durante o jogo, o aplicativo perdeu a conexão com a internet?', [
    'Sim',
    'Não',
    'Não sei'
  ], { required: true });

  addParagraph_(form, 'Se perdeu, o que você entendeu na hora e o que fez?', false);
}

function addOverall_(form) {
  addSection_(form, 'No geral', 'Diga o quanto você concorda com cada frase, de 1 a 5.');

  const statements = [
    'Consegui usar o aplicativo sem ajuda.',
    'Entendi o que aconteceu no jogo.',
    'Os sons e as vibrações me ajudaram.',
    'Confiei nas informações que ouvi.',
    'A narração soou como a de um narrador de rádio, e não como uma leitura de dados.',
    'Eu usaria o aplicativo em um jogo de verdade.'
  ];

  statements.forEach(function (statement) {
    addScale_(form, statement, 'Discordo totalmente', 'Concordo totalmente', true);
  });
}

function addClosing_(form) {
  addSection_(form, 'Para terminar', 'Não escreva seu nome.');

  addParagraph_(form, 'O que você mudaria primeiro no aplicativo?', false);
  addParagraph_(form, 'Quer contar mais alguma coisa?', false);
}

// MARK: - Helpers
//
// Trailing underscores keep these out of the "run" menu of the script editor, which is how Apps
// Script marks private functions.

function addSection_(form, title, helpText) {
  const page = form.addPageBreakItem();
  page.setTitle(title);

  if (helpText) {
    page.setHelpText(helpText);
  }
}

function addChoice_(form, title, labels, options) {
  const item = form.addMultipleChoiceItem();
  item.setTitle(title);
  item.setChoiceValues(labels);

  if (options.other) {
    item.showOtherOption(true);
  }

  item.setRequired(options.required === true);
  return item;
}

function addText_(form, title, required) {
  const item = form.addTextItem();
  item.setTitle(title);
  item.setRequired(required);
  return item;
}

function addParagraph_(form, title, required) {
  const item = form.addParagraphTextItem();
  item.setTitle(title);
  item.setRequired(required);
  return item;
}

function addScale_(form, title, lowLabel, highLabel, required) {
  const item = form.addScaleItem();
  item.setTitle(title);
  item.setBounds(1, 5);
  item.setLabels(lowLabel, highLabel);
  item.setRequired(required);
  return item;
}
