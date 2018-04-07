# Customizing UINavigationBar

NavBar demonstrates using `UINavigationController` and `UIViewController` classes together as building blocks to your application's user interface. Use it as a reference when starting the development of your new application. The various pages in this sample exhibit different ways of how to modify the navigation bar directly, using the appearance proxy, and by modifying the view controller's `UINavigationItem`. Among the levels of customization are varying appearance styles, and applying custom left and right buttons known as `UIBarButtonItems`.

## Custom Right View

This example demonstrates placing three kinds of `UIBarButtonItems` on the right side of the navigation bar: a button with a title, a button with an image, and a button with a `UISegmentedControl`. An additional segmented control allows the user to toggle between the three. The initial bar button is defined in the storyboard, by dragging a `UIBarButtonItem` out of the object library and into the navigation bar.  `CustomRightViewController` also shows how to create and add each button type using code.

## Custom Title View

This example demonstrates adding a `UISegmentedControl` as the custom title view (center) of the navigation bar.

## Navigation Prompt

This example demonstrates customizing the 'prompt' property of a `UINavigationItem` to display a custom line of text above the navigation bar.

## Custom Appearance

This example demonstrates customizing the background of a navigation bar, applying a custom bar tint color or background image.

## Custom Back Button

This example demonstrates using an image as the back button without any back button text and without the chevron that normally appears next to the back button.

## Large Title

This example demonstrates customizing the navigation bar by setting its title at a larger size, thus increasing the size of the `UINavigationBar`.

## Using the sample

The sample launches to a list of examples, each focusing on a different aspect of customizing the navigation bar.

### Bar Style
Click the "Style" button to the left of the main page to change the navigation bar's style or `UIBarStyle.` This will take you to an action sheet where you can change the background's appearance (default, black-opaque, or black-translucent).

    NOTE: A navigation controller determines its preferredStatusBarStyle based upon the navigation bar style. This is why the status bar always appears correct after changing the bar style, without any extra code required.


# REQUIREMENTS

## BUILD
iOS 11.0 SDK or later

## RUNTIME
iOS 10.0 or later


# PACKAGING LIST

`AppDelegate`: The application delegate class.

`MainViewController`: The application's main (initial) view controller.

`CustomRightViewController`: Demonstrates configuring various types of controls as the right bar item of the navigation bar.
    
`CustomTitleViewController`: Demonstrates configuring the navigation bar to use a UIView as the title.
    
`NavigationPromptViewController`: Demonstrates displaying text above the navigation bar.

`CustomAppearanceViewController`: Demonstrates applying a custom background to a navigation bar.
    
`CustomBackButtonNavController`: UINavigationController subclass used for targeting appearance proxy changes in the Custom Back Button example.
    
`CustomBackButtonDetailViewController`: The detail view controller in the Custom Back Button example.
    
`CustomBackButtonViewController`: Demonstrates using a custom back button image with no chevron and not text.

`LargeTitleViewController`: Demonstrates using large title for the navigation bar.


Copyright (C) 2008-2017 Apple Inc. All rights reserved.
