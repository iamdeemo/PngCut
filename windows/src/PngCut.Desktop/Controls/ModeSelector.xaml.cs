using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using PngCut.Core.Models;

namespace PngCut.Desktop.Controls;

public partial class ModeSelector : UserControl
{
    private static readonly TimeSpan ResponsiveDuration = TimeSpan.FromMilliseconds(200);
    private static readonly IEasingFunction ResponsiveEasing = new CubicEase
    {
        EasingMode = EasingMode.EaseInOut
    };
    private static readonly Color PrimaryTextColor = Color.FromRgb(0x25, 0x2A, 0x31);

    public static readonly DependencyProperty SelectedModeProperty =
        DependencyProperty.Register(
            nameof(SelectedMode),
            typeof(CompressionMode),
            typeof(ModeSelector),
            new FrameworkPropertyMetadata(
                CompressionMode.Lossless,
                FrameworkPropertyMetadataOptions.BindsTwoWayByDefault,
                SelectedModeChanged));

    public ModeSelector()
    {
        InitializeComponent();
        UpdateTextColors(CompressionMode.Lossless, animate: false);
    }

    public CompressionMode SelectedMode
    {
        get => (CompressionMode)GetValue(SelectedModeProperty);
        set => SetValue(SelectedModeProperty, value);
    }

    private static void SelectedModeChanged(DependencyObject dependencyObject, DependencyPropertyChangedEventArgs args)
    {
        var selector = (ModeSelector)dependencyObject;
        var mode = (CompressionMode)args.NewValue;
        selector.AnimateSelection(mode);
        selector.UpdateTextColors(mode, animate: true);
    }

    private void AnimateSelection(CompressionMode mode)
    {
        var animation = new DoubleAnimation
        {
            To = mode == CompressionMode.Lossless ? 0 : 88,
            Duration = ResponsiveDuration,
            EasingFunction = ResponsiveEasing
        };
        SelectionTransform.BeginAnimation(TranslateTransform.XProperty, animation);
    }

    private void UpdateTextColors(CompressionMode mode, bool animate)
    {
        if (LosslessMode == null || BalancedMode == null)
        {
            return;
        }

        UpdateForeground(LosslessMode, mode == CompressionMode.Lossless ? Colors.White : PrimaryTextColor, animate);
        UpdateForeground(BalancedMode, mode == CompressionMode.Balanced ? Colors.White : PrimaryTextColor, animate);
    }

    private static void UpdateForeground(Button button, Color color, bool animate)
    {
        var brush = button.Foreground as SolidColorBrush;
        if (brush == null || brush.IsFrozen)
        {
            brush = new SolidColorBrush(color);
            button.Foreground = brush;
        }

        var currentColor = brush.Color;
        brush.BeginAnimation(SolidColorBrush.ColorProperty, null);
        brush.Color = currentColor;
        if (!animate)
        {
            brush.Color = color;
            return;
        }

        brush.BeginAnimation(SolidColorBrush.ColorProperty, new ColorAnimation
        {
            To = color,
            Duration = ResponsiveDuration,
            EasingFunction = ResponsiveEasing
        });
    }

    private void LosslessMode_OnClick(object sender, RoutedEventArgs e) =>
        SelectedMode = CompressionMode.Lossless;

    private void BalancedMode_OnClick(object sender, RoutedEventArgs e) =>
        SelectedMode = CompressionMode.Balanced;
}
