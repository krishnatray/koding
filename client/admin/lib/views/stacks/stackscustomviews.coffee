kd                              = require 'kd'
globals                         = require 'globals'
remote                          = require('app/remote').getInstance()

_                               = require 'lodash'
hljs                            = require 'highlight.js'
Encoder                         = require 'htmlencode'
dateFormat                      = require 'dateformat'

whoami                          = require 'app/util/whoami'
FSHelper                        = require 'app/util/fs/fshelper'
showError                       = require 'app/util/showError'
applyMarkdown                   = require 'app/util/applyMarkdown'

GitHub                          = require 'app/extras/github/github'
CustomViews                     = require 'app/commonviews/customviews'
IDEEditorPane                   = require 'ide/workspace/panes/ideeditorpane'
CredentialListItem              = require './credentiallistitem'
ComputeController_UI            = require 'app/providers/computecontroller.ui'
AccountCredentialList           = require 'account/accountcredentiallist'
AccountCredentialListController = require 'account/views/accountcredentiallistcontroller'

StackRepoUserItem               = require './stackrepouseritem'
StackTemplateList               = require './stacktemplatelist'
StackTemplateListController     = require './stacktemplatelistcontroller'


module.exports = class StacksCustomViews extends CustomViews

  # This will be used if stack template is not defined yet
  DEFAULT_TEMPLATE = """
  {
    "provider": {
      "aws": {
        "access_key": "${var.access_key}",
        "secret_key": "${var.secret_key}",
        "region": "eu-central-1"
      }
    },
    "resource": {
      "aws_instance": {
        "example": {
          "instance_type": "t2.micro",
          "ami": "ami-936d9d93"
        }
      }
    }
  }
  """

  STEPS          =
    CUSTOM_STACK : [
        { title  : 'Select Provider' }
        { title  : 'Credentials' }
        { title  : 'Bootstrap' }
        { title  : 'Define your Stack' }
        { title  : 'Complete' }
      ]
    REPO_FLOW    : [
        { title  : 'Select Repo' }
        { title  : 'Locate File' }
        { title  : 'Fetch Template' }
        { title  : 'Credentials' }
        { title  : 'Bootstrap' }
        { title  : 'Complete' }
      ]


  parseTerraformOutput = (response) ->

    # An example of a valid stack template
    # ------------------------------------
    # title: "Default stack",
    # description: "Koding's default stack template for new users",
    # machines: [
    #   {
    #     "label" : "koding-vm-0",
    #     "provider" : "koding",
    #     "instanceType" : "t2.micro",
    #     "provisioners" : [
    #         "devrim/koding-base"
    #     ],
    #     "region" : "us-east-1",
    #     "source_ami" : "ami-a6926dce"
    #   }
    # ],

    out = machines: []

    {machines} = response

    for machine, index in machines

      {label, provider, region} = machine
      {instance_type, ami} = machine.attributes

      out.machines.push {
        label, provider, region
        source_ami   : ami
        instanceType : instance_type
        provisioners : [] # TODO what are we going to do with provisioners? ~ GG
      }

    console.info "[parseTerraformOutput]", out.machines

    return out.machines


  fetchGithubRepos = (options, callback) ->

    { oauth_data } = options
    { Github }     = remote.api

    Github.api method: 'user.getOrgs', (err, orgs) ->

      kd.warn err  if err

      orgs ?= []

      # to make identical users and orgs assigning
      # username to login field as well
      oauth_data.login = oauth_data.username
      users = [oauth_data]

      Github.api
        method      : 'repos.getFromUser'
        options     :
          user      : users.first.username
          type      : 'owner'
          sort      : 'pushed'
          direction : 'desc'

      , (err, repos) ->

        users.first.err   = err
        users.first.repos = repos ? []

        callback null, {orgs, users}


  handleCheckTemplate = (options, callback) ->

    { stackTemplate } = options
    { computeController } = kd.singletons

    computeController.getKloud()
      .checkTemplate { stackTemplateId: stackTemplate._id }
      .nodeify callback


  fetchRepoFile = (options, callback) ->

    { Github } = remote.api
    { repo, location, ref } = options

    Github.api
      method  : 'repos.getContent'
      options :
        repo  : repo.name
        user  : repo.owner.login
        path  : location
        ref   : ref

    , callback


  updateStackTemplate = (data, callback) ->

    { template, credential, title, stackTemplate, machines } = data

    title     or= 'Default stack template'
    credentials = [credential.publicKey]  if credential

    if stackTemplate
      dataToUpdate = if machines \
        then {machines} else {title, template, credentials}
      stackTemplate.update dataToUpdate, (err) ->
        callback err, stackTemplate
    else
      remote.api.JStackTemplate.create {
        title, template, credentials
      }, callback


  setGroupTemplate = (stackTemplate, callback) ->

    { groupsController } = kd.singletons

    currentGroup = groupsController.getCurrentGroup()
    { slug }     = currentGroup

    if slug is 'koding'
      message = 'Setting stack template for koding is disabled'
      new kd.NotificationView title: message
      return callback {message}

    currentGroup.modify stackTemplates: [ stackTemplate._id ], (err) ->
      return callback err  if err

      new kd.NotificationView
        title: "Group (#{slug}) stack has been saved!"

      callback()


  fetchAndShowCredentialData = (credential, outputView) ->

    outputView.addContent 'Fetching latest data...'

    credential.fetchData (err, data) ->
      if err
        outputView.addContent 'Failed: ', err.message
      else

        try
          cred = JSON.stringify data.meta, null, 2
        catch e
          outputView.addContent 'Failed to parse:', e
          return

        outputView
          .addContent cred
          .addContent 'You can continue to next step.'
          .emit 'BootstrappingDone'


  handleBootstrap = (outputView, credential, button) ->

    outputView.addContent 'Bootstrapping started...'

    publicKeys = [credential.publicKey]

    { computeController } = kd.singletons

    computeController.getKloud()

      .bootstrap { publicKeys }

      .then (response) ->

        if response
          outputView.addContent 'Bootstrap completed successfully'
          fetchAndShowCredentialData credential, outputView
        else
          outputView.addContent 'Bootstrapping completed but something went wrong.'

        console.log '[KLOUD:Bootstrap]', response

      .catch (err) ->

        outputView.addContent 'Bootstrapping failed:', err.message
        console.warn '[KLOUD:Bootstrap:Fail]', err

      .finally button.bound 'hideLoader'


  handleNewCredential = (views, provider, button) ->

    {controller} = views.credentialList
    view = controller.getView()
    button.disable()
    view.hide()

    form = controller.showAddCredentialFormFor provider
    form.on 'Cancel', view.bound   'show'
    form.on 'Cancel', button.bound 'enable'

    kd.utils.defer -> form.inputs.title?.focus()

    # After adding credential, we are sharing it with the current
    # group, so anyone in this group can use this credential ~ GG
    form.on 'CredentialAdded', (credential) ->
      {slug} = kd.singletons.groupsController.getCurrentGroup()
      credential.shareWith {target: slug}, (err) ->
        console.warn 'Failed to share credential:', err  if err
        button.enable()
        view.show()


  _.assign @views,


    mainLoader: (message) =>

      container = @views.container 'main-loader'
      container.addSubView new kd.LoaderView
        showLoader : yes
        size       :
          width    : 40
          height   : 40

      @addTo container, text: message

      return container


    outputView: (options) =>

      options.cssClass = kd.utils.curry 'output-view', options.cssClass
      options.tagName  = 'pre'
      container        = @views.view options
      code             = @views.view tagName : 'code'

      container.addSubView code

      container.addContent = (content...) ->
        content = content.join ' '
        content = "[#{dateFormat Date.now(), 'HH:MM:ss'}] #{content}\n"
        code.setPartial hljs.highlight('profile', content).value
        return container

      container.setContent = (content...) ->
        content = content.join ' '
        code.updatePartial hljs.highlight('profile', content).value
        return container

      return container


    editorView: (options) =>

      kd.singletons.appManager.require 'IDE'

      {content} = options

      content   = Encoder.htmlDecode content
      file      = FSHelper.createFileInstance path: 'localfile:/stack.json'

      editorView = new IDEEditorPane {
        cssClass: 'editor-view'
        file, content, delegate: this
      }

      editorView.setCss background: 'black'

      return editorView


    button: (options) ->
      options.cssClass ?= ''
      new kd.ButtonView options


    menuButton: (options) ->

      {menu, callback} = options

      button    = null
      _menu     = null
      menuItems = {}

      Object.keys(menu).forEach (key) ->
        menuItems[key] =
          callback     : ->
            callback menu[key]
            _menu.destroy()

      options.callback = ->
        _menu = new kd.ContextMenu
          cssClass    : 'menu-button-menu'
          delegate    : button
          y           : button.getY() + button.getHeight()
          x           : button.getX() - 5
          width       : button.getWidth()
          arrow       :
            placement : 'top'
            margin    : -button.getWidth() / 2
        , menuItems

      button = new kd.ButtonView options

      return button


    navButton: (options, name) =>
      options.cssClass = kd.utils.curry 'solid compact light-gray nav', name
      options.title = name.capitalize()
      @views.button options


    navCancelButton: (options) =>
      options.cssClass = 'solid compact light-gray nav cancel'
      @views.button options


    input: (options, name) =>

      {label, value} = options

      new kd.FormViewWithFields
        fields: input: {name, label, defaultValue: value}


    initialView: (callback) =>

      container = @views.container 'stacktemplates'

      { groupsController } = kd.singletons
      currentGroup = groupsController.getCurrentGroup()

      views = @addTo container,
        text_header       : 'Compute Stack Templates'
        container_top     :
          text_intro      : "Stack Templates are awesome because when a user
                             joins your group you can preconfigure their work
                             environment by defining stacks.
                             Learn more about stacks"
          menuButton      :
            title         : 'Configure a Stack'
            cssClass      : 'solid compact green action'
            menu          :
              'Create from scratch' : 'create-new'
              'Use from repo'       : 'from-repo'
            callback      : callback
        stackTemplateList :
          group           : currentGroup

      templateList = views.stackTemplateList.__view
      templateList.on 'ItemSelected', callback

      return container


    stackTemplateList: (options) ->

      listView   = new StackTemplateList
      controller = new StackTemplateListController
        view       : listView
        wrapper    : no
        scrollView : no

      __view = controller.getView()
      return { __view, controller }


    stepSelectRepo: (options) =>

      {callback, cancelCallback, data} = options
      container = @views.container 'step-select-repo'

      views     = @addTo container,
        stepsHeaderView   :
          steps           : STEPS.REPO_FLOW
          selected        : 1
        text              : "We need to locate your configuration file first so
                             that we can understand what we are going to do
                             when a user joins to your team.<br />
                             So please tell us where your stack configuration
                             file is."
        providersView     :
          providers       : ['github', 'bitbucket']
          enabled         : ['github']
        navButton_cancel  :
          callback        : cancelCallback

      views.providersView.on 'ItemSelected', (provider) ->

        whoami().fetchOAuthInfo (err, services) ->
          return  if showError err

          unless oauth = services?[provider]
            showError "You need to authenticate with #{provider} first."
            kd.singletons.router.handleRoute '/Admin/Integrations'
          else
            data.repo_provider = provider
            data.oauth_data    = oauth
            callback data

      return container


    stepLocateFile: (options) =>

      { callback, cancelCallback, data } = options
      { repo_provider, oauth_data } = data

      container = @views.container 'step-locate-file'

      views     = @addTo container,
        stepsHeaderView   :
          steps           : STEPS.REPO_FLOW
          selected        : 2
        repoListView      : { oauth_data }
        navCancelButton   :
          title           : '< Select another provider'
          callback        : ->
            cancelCallback data

      views.repoListView.on 'RepoSelected', (selected_repo) ->
        callback { repo_provider, selected_repo, oauth_data }

      return container


    stepFetchTemplate: (options) =>

      { callback, cancelCallback, data } = options
      { repo_provider, selected_repo }   = data

      container = @views.container 'step-fetch-template'

      views     = @addTo container,
        stepsHeaderView   :
          steps           : STEPS.REPO_FLOW
          selected        : 3
        mainLoader        : 'Fetching template...'
        outputView        :
          cssClass        : 'hidden'
        navCancelButton   :
          title           : '< Select another repo'
          callback        : ->
            cancelCallback data

      { outputView, mainLoader } = views

      fetchRepoFile selected_repo, (err, template) ->

        mainLoader.hide()
        outputView.show()

        console.log err, template

        if err
          content = err?.message
        else if template?.content?
          content = atob template.content
        else
          content = 'Something went wrong, please try again.'

        outputView.setContent content


      return container


    stepSelectProvider: (options) =>

      {callback, cancelCallback, data} = options
      container = @views.container 'step-provider'

      views     = @addTo container,
        stepsHeaderView :
          steps         : STEPS.CUSTOM_STACK
          selected      : 1
        text            : "You need to select a provider first"
        providersView   :
          providers     : Object.keys globals.config.providers
          enabled       : ['aws']
        navButton_cancel:
          callback      : cancelCallback

      views.providersView.on 'ItemSelected', (provider) ->
        data.provider = provider
        callback data

      return container


    repoList: (options) =>

      controller    = new kd.ListViewController
        viewOptions :
          itemClass : StackRepoUserItem
          cssClass  : 'repo-user-list'

      __view = controller.getListView()
      return { __view, controller }


    repoListView: (options) =>

      container    = @views.container 'repo-listview'
      loader       = @addTo container,
        mainLoader : 'Fetching repositories list...'

      fetchGithubRepos options, (err, repo_data) =>

        showError err

        loader.hide()

        views        = @addTo container,
          text       : "Github: Select a repository from your account"
          repoList   : options

        {controller, __view: repoList} = views.repoList

        {orgs, users} = repo_data
        controller.replaceAllItems users.concat orgs

        container.forwardEvent repoList, 'RepoSelected'

      return container


    credentialList: (options) =>

      { provider, stackTemplate } = options

      listView   = new AccountCredentialList
        itemClass   : CredentialListItem
        itemOptions : { stackTemplate }

      controller = new AccountCredentialListController
        view        : listView
        wrapper     : no
        scrollView  : no
        provider    : provider

      __view = controller.getView()
      return { __view, controller }


    stepSetupCredentials: (options) =>

      { data, callback, cancelCallback } = options
      { provider, stackTemplate } = data

      container  = @views.container 'step-creds'
      views      = @addTo container,
        stepsHeaderView :
          steps         : STEPS.CUSTOM_STACK
          selected      : 2
        container_top   :
          text_intro    : "To be able to use this provider <strong>you need to
                           select a verified credential</strong> below, if you
                           don't have a verified credential you won't be able
                           to setup your stack for your team."
          button        :
            title       : 'Add New Credential'
            cssClass    : 'solid compact green action'
            callback    : ->
              handleNewCredential views, provider, this
        credentialList  : { provider, stackTemplate }
        navCancelButton :
          title         : '< Select another provider'
          callback      : ->
            cancelCallback data

      credentialList = views.credentialList.__view
      credentialList.on 'ItemSelected', (credential) ->
        data.credential = credential
        callback data

      return container


    stepBootstrap: (options) =>

      {callback, cancelCallback, data} = options
      {provider, credential, stackTemplate} = data

      container = @views.container 'step-bootstrap'

      container.setClass 'has-markdown'

      views     = @addTo container,
        stepsHeaderView :
          steps         : STEPS.CUSTOM_STACK
          selected      : 3
        container       :
          mainLoader    : 'Checking bootstrap status...'
        navCancelButton :
          title         : '< Select another credential'
          callback      : -> cancelCallback data

      credential.isBootstrapped (err, state) =>

        views.container.destroySubViews()

        {outputView} = @addTo views.container,

          container_top :
            text_intro  : "Bootstrapping for given credential is required.
                           With this process we will create necessary
                           settings on your #{provider} account.
                           Which you can see them from provider's control
                           panel as well."
            button      :
              title     : 'Bootstrap Now'
              cssClass  : \
                "solid compact green action #{if state then 'hidden' else ''}"
              loader    : yes
              callback  : ->
                outputView.show()
                handleBootstrap outputView, credential, this

          outputView    :
            cssClass    : 'bootstrap-output hidden'

        outputView.on 'BootstrappingDone', => @addTo container,
          button        :
            title       : 'Continue'
            cssClass    : 'solid compact green nav next'
            callback    : ->
              callback {provider, credential, stackTemplate}

        if state
          outputView.show()
          outputView.addContent 'Bootstrapping completed for this credential'
          fetchAndShowCredentialData credential, outputView

      return container


    stepDefineStack: (options) =>

      {callback, cancelCallback, data}      = options
      {provider, credential, stackTemplate} = data or {}

      container = @views.container 'step-define-stack'
      content   = stackTemplate?.template?.content or DEFAULT_TEMPLATE
      views     = @addTo container,
        stepsHeaderView :
          steps         : STEPS.CUSTOM_STACK
          selected      : 4
        input_title     :
          label         : 'Stack Template Title'
          value         : stackTemplate?.title or 'Default Template'
        editorView      : {content}
        navCancelButton :
          title         : '< Boostrap Credential'
          callback      : -> cancelCallback data
        button_save     :
          title         : 'Save & Test >'
          cssClass      : 'solid compact green nav next'
          callback      : ->

            {title}  = views.input_title.getData()
            template = views.editorView.getValue()

            updateStackTemplate {
              title, template, credential, stackTemplate
            }, (err, _stackTemplate) ->
              return  if showError err

              callback {
                stackTemplate: _stackTemplate, credential, provider
              }

      return container


    stepComplete: (options) =>

      {callback, cancelCallback, data}      = options
      {stackTemplate, credential, provider} = data

      container = @views.container 'step-complete'

      container.setClass 'has-markdown'

      views = @addTo container,
        stepsHeaderView :
          steps         : STEPS.CUSTOM_STACK
          selected      : 5
        container       :
          mainLoader    : 'Processing template...'

      handleCheckTemplate {stackTemplate}, (err, response) =>

        console.log '[KLOUD:checkTemplate]', err, response

        @addTo container,
          navCancelButton :
            title         : '< Edit Template'
            callback      : -> cancelCallback data

        views.container.destroySubViews()

        outputView   = @addTo views.container,
          outputView :
            cssClass : 'plan-output'

        if err or not response
          outputView
            .addContent 'Something went wrong with the template:'
            .addContent err?.message or 'No response from Kloud'
        else

          machines = parseTerraformOutput response

          outputView
            .addContent 'Template check complete succesfully'
            .addContent 'Following machines will be created:'
            .addContent JSON.stringify machines, null, 2
            .addContent 'Click Complete to set this stack as default stack'

          @addTo container,
            button_save     :
              title         : 'Complete'
              cssClass      : 'solid compact green nav next'
              callback      : ->
                updateStackTemplate {
                  stackTemplate, machines
                }, (err, stackTemplate) ->
                  return  if showError err
                  callback stackTemplate

      return container


    providersView: (options) =>

      {providers, enabled} = options
      enabled  ?= providers

      container = @views.container 'providers'

      providers.forEach (provider) =>

        return  if provider in ['custom', 'managed']

        name = globals.config.providers[provider]?.name or provider

        @addTo container,
          button     :
            title    : name
            cssClass : provider
            disabled : provider not in enabled
            callback : ->
              container.emit 'ItemSelected', provider

      return container


    stepsHeader: (options) =>

      { title, index, selected } = options

      container = @views.container "#{if selected then 'selected' else ''}"

      @addTo container,
        text_step  : index
        text_title : title

      return container


    stepsHeaderView: (options) =>

      { steps, selected } = options

      container = @views.container 'steps-view'

      @addTo container, view :
        cssClass : 'vline'
        tagName  : 'cite'

      steps = steps.slice 0
      steps.forEach (step, index) =>

        step.index    = index + 1
        step.selected = selected? and selected is step.index

        @addTo container, stepsHeader: step

      return container
